import SwiftUI
import UIKit
import AVFoundation
import Observation

@Observable
final class ClipRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    enum State { case idle, ready, recording, unavailable }

    let session: AVCaptureSession = AVCaptureMultiCamSession.isMultiCamSupported
        ? AVCaptureMultiCamSession()
        : AVCaptureSession()
    private static let sessionQueue = DispatchQueue(label: "com.cassie.AISetlog.capture-session")
    private let movieOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored private let inputLock = NSLock()
    @ObservationIgnored private var _videoInput: AVCaptureDeviceInput?
    private var videoInput: AVCaptureDeviceInput? {
        get {
            access(keyPath: \.videoInput)
            return inputLock.withLock { _videoInput }
        }
        set {
            withMutation(keyPath: \.videoInput) { inputLock.withLock { _videoInput = newValue } }
        }
    }
    private var position: AVCaptureDevice.Position = .back

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var connectionObservers: [NSObjectProtocol] = []

    private let secondaryOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored private var _secondaryInput: AVCaptureDeviceInput?
    private var secondaryInput: AVCaptureDeviceInput? {
        get {
            access(keyPath: \.secondaryInput)
            return inputLock.withLock { _secondaryInput }
        }
        set {
            withMutation(keyPath: \.secondaryInput) { inputLock.withLock { _secondaryInput = newValue } }
        }
    }
    private var secondaryConnections: [AVCaptureConnection] = []
    private weak var secondaryPreviewLayer: AVCaptureVideoPreviewLayer?

    private(set) var isDualCamera = false
    private(set) var isSwapped = false
    var insetRect: CGRect = PiPInsetLayout.load() {
        didSet { PiPInsetLayout.save(insetRect) }
    }
    private var pendingPrimary: URL??
    private var pendingPrimaryCamera: String?
    private var pendingSecondaryCamera: String?
    private var recordingSideways = false
    private var pendingSecondary: URL??

    var supportsDualCamera: Bool {
        session is AVCaptureMultiCamSession && !Self.isSimulated
    }

    private var isConfigured = false
    var orientation: Challenge.Orientation = .portrait {
        didSet { applyOrientation() }
    }
    var forcedLandscape = false {
        didSet { applyAngles() }
    }
    var cameraStyle: CameraStyle = .standard

    private(set) var state: State = .idle
    private(set) var clipURL: URL? {
        didSet {
            #if DEBUG
            if let clipURL { Self.logTakeGeometry(clipURL, sideways: forcedLandscape) }
            #endif
        }
    }
    private(set) var recordedAt: Date?

    private(set) var failureCount = 0
    private(set) var lastFailure: Date?

    private(set) var hasAudioAccess = true

    private(set) var zoomCapabilities: CameraZoom = .unavailable
    private(set) var zoom: CGFloat = 1

    var zoomPresets: [CGFloat] { zoomCapabilities.presets() }

    private static let backCameraTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera,
        .builtInDualWideCamera,
        .builtInDualCamera,
        .builtInWideAngleCamera,
    ]

    private static let frontCameraTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]

    private func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let preferred = position == .front ? Self.frontCameraTypes : Self.backCameraTypes
        for type in preferred {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first
    }

    #if DEBUG && targetEnvironment(simulator)
    static var isSimulated: Bool {
        UserDefaults.standard.bool(forKey: "simulatedCamera")
    }
    private var simulatedTake: Task<Void, Never>?
    private var simulatedSeconds: Double = 0
    private var simulatedFinishing = false
    #else
    static var isSimulated: Bool { false }
    #endif

    func configure() async {
        #if DEBUG && targetEnvironment(simulator)
        if Self.isSimulated {
            hasAudioAccess = true
            state = .ready
            return
        }
        #endif
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            state = .unavailable
            return
        }
        let hasAudioAccess = await AVCaptureDevice.requestAccess(for: .audio)
        self.hasAudioAccess = hasAudioAccess

        let configured = await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                if isConfigured {
                    continuation.resume(returning: true)
                    return
                }

                session.beginConfiguration()
                if session.canSetSessionPreset(.high) {
                    session.sessionPreset = .high
                }

                guard
                    let camera = camera(for: position),
                    Self.prepare(camera, for: session),
                    let input = try? AVCaptureDeviceInput(device: camera),
                    session.canAddInput(input),
                    session.canAddOutput(movieOutput)
                else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }

                session.addInput(input)
                videoInput = input

                if hasAudioAccess,
                   let mic = AVCaptureDevice.default(for: .audio),
                   let audioInput = try? AVCaptureDeviceInput(device: mic),
                   session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }

                session.addOutput(movieOutput)
                session.commitConfiguration()
                isConfigured = true
                continuation.resume(returning: true)
            }
        }

        guard configured else {
            state = .unavailable
            return
        }
        if connectionObservers.isEmpty {
            let center = NotificationCenter.default
            let reapply: (Notification) -> Void = { [weak self] _ in
                Task { @MainActor in self?.applyAngles() }
            }
            connectionObservers = [
                center.addObserver(
                    forName: AVCaptureInput.Port.formatDescriptionDidChangeNotification,
                    object: nil, queue: nil, using: reapply),
                center.addObserver(
                    forName: AVCaptureSession.didStartRunningNotification,
                    object: session, queue: nil, using: reapply),
            ]
        }
        applyOrientation()
        refreshZoom()
        state = .ready
    }

    deinit {
        connectionObservers.forEach(NotificationCenter.default.removeObserver)
    }


    private(set) var isTorchOn = false

    var canUseTorch: Bool { torchDevice != nil }

    private var torchDevice: AVCaptureDevice? {
        [videoInput?.device, secondaryInput?.device]
            .compactMap { $0 }
            .first { $0.position == .back && $0.hasTorch && $0.isTorchModeSupported(.on) }
    }

    func toggleTorch() {
        isTorchOn.toggle()
        applyTorch()
    }

    private func applyTorch() {
        guard let device = torchDevice else { return }
        let on = isTorchOn
        Self.sessionQueue.async {
            do { try device.lockForConfiguration() } catch { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }


    func setZoom(_ display: CGFloat) {
        guard let device = videoInput?.device else { return }
        let clamped = zoomCapabilities.clampedDisplay(display)
        zoom = clamped

        let factor = zoomCapabilities.factor(forDisplay: clamped)
        Self.sessionQueue.async {
            do {
                try device.lockForConfiguration()
            } catch {
                return
            }
            device.videoZoomFactor = min(
                max(factor, device.minAvailableVideoZoomFactor),
                device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        }
    }

    private func refreshZoom() {
        guard let device = videoInput?.device else {
            zoomCapabilities = .unavailable
            zoom = 1
            return
        }
        zoomCapabilities = CameraZoom(device: device)
        setZoom(1)
    }


    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        applyOrientation()
        Self.sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            Task { @MainActor in self.applyTorch() }
        }
    }

    private func applyOrientation() {
        applyAngles()
    }

    private func applyAngles() {
        let sideways = forcedLandscape
        Self.sessionQueue.async { [self] in
            guard let device = videoInput?.device else { return }
            let native = CameraOrientation.nativePortrait(device)
            Self.setFileAngle(
                CameraOrientation.captureAngle(
                    sideways: sideways, nativePortrait: native, front: device.position == .front),
                mirrored: Self.mirrorsLikePreview(previewLayer?.connection, front: device.position == .front),
                on: movieOutput.connection(with: .video))
            Self.setAngle(
                CameraOrientation.previewAngle(nativePortrait: native),
                on: previewLayer?.connection)

            if let other = secondaryInput?.device {
                let otherNative = CameraOrientation.nativePortrait(other)
                for connection in secondaryConnections {
                    if connection.videoPreviewLayer == nil {
                        Self.setFileAngle(
                            CameraOrientation.captureAngle(
                                sideways: sideways, nativePortrait: otherNative,
                                front: other.position == .front),
                            mirrored: Self.mirrorsLikePreview(secondaryConnections.first { $0.videoPreviewLayer != nil }, front: other.position == .front), on: connection)
                    } else {
                        Self.setAngle(
                            CameraOrientation.previewAngle(nativePortrait: otherNative), on: connection)
                    }
                }
            }
            #if DEBUG
            logAngles(sideways: sideways)
            #endif
        }
    }

    private static func setAngle(_ angle: CGFloat, on connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private static func mirrorsLikePreview(_ preview: AVCaptureConnection?, front: Bool) -> Bool {
        false
    }

    private static func setFileAngle(
        _ angle: CGFloat, mirrored: Bool, on connection: AVCaptureConnection?
    ) {
        guard let connection else { return }
        setAngle(angle, on: connection)
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    #if DEBUG
    nonisolated static func diag(_ items: Any...) {
        print(items.map { "\($0)" }.joined(separator: " "))
        fflush(stdout)
    }

    nonisolated static func diagName(_ device: AVCaptureDevice?) -> String {
        guard let device else { return "none" }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let side = device.position == .front ? "front" : "back"
        return "\(side)/\(device.deviceType.rawValue.split(separator: ".").last ?? "")/format=\(dims.width)x\(dims.height)"
            + "/nativePortrait=\(CameraOrientation.nativePortrait(device))"
    }

    private func logAngles(sideways: Bool) {
        let file = movieOutput.connection(with: .video)
        Self.diag("[诊断] angles sideways=\(sideways) primary=\(Self.diagName(videoInput?.device))",
              "file=\(file?.videoRotationAngle ?? -1) mirrored=\(file?.isVideoMirrored ?? false)",
              "preview=\(previewLayer?.connection?.videoRotationAngle ?? -1)")
        for connection in secondaryConnections {
            Self.diag("[诊断]   inset=\(Self.diagName(secondaryInput?.device))",
                  connection.videoPreviewLayer == nil ? "file" : "preview",
                  "=\(connection.videoRotationAngle) mirrored=\(connection.isVideoMirrored)")
        }
    }
    #endif

    #if DEBUG
    nonisolated static func logTakeGeometry(_ url: URL, sideways: Bool, label: String = "final") {
        Task.detached {
            guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
                  let natural = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform)
            else { return }
            let shown = natural.applying(transform)
            diag("[诊断] take \(label) sideways=\(sideways) natural=\(natural) transform=\(transform)",
                  "shown=\(abs(shown.width))x\(abs(shown.height))")
        }
    }
    #endif
    func flipCamera() {
        guard state == .ready else { return }
        if isDualCamera {
            isSwapped.toggle()
            return
        }
        let newPosition: AVCaptureDevice.Position = position == .front ? .back : .front
        Self.sessionQueue.sync {
            session.beginConfiguration()
            if let videoInput { session.removeInput(videoInput) }
            if let camera = camera(for: newPosition),
               Self.prepare(camera, for: session),
               let input = try? AVCaptureDeviceInput(device: camera),
               session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
                position = newPosition
            } else if let videoInput, session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            session.commitConfiguration()
        }
        applyOrientation()
        refreshZoom()
        applyTorch()
    }

    func startRecording(seconds: Double) {
        guard state == .ready else { return }
        #if DEBUG && targetEnvironment(simulator)
        if Self.isSimulated {
            recordedAt = .now
            state = .recording
            simulatedSeconds = seconds
            simulatedTake = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.finishSimulatedTake()
            }
            return
        }
        #endif

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).mov")
        recordedAt = .now
        state = .recording
        let sideways = forcedLandscape
        recordingSideways = sideways

        Self.sessionQueue.async { [self] in
            if !session.isRunning { session.startRunning() }
            guard session.isRunning,
                  movieOutput.connection(with: .video)?.isActive == true else {
                Task { @MainActor in
                    self.recordedAt = nil
                    self.state = .unavailable
                }
                return
            }

            movieOutput.maxRecordedDuration = CMTime(
                seconds: seconds,
                preferredTimescale: 600)
            if let device = videoInput?.device {
                Self.setFileAngle(
                    CameraOrientation.captureAngle(
                        sideways: sideways, nativePortrait: CameraOrientation.nativePortrait(device),
                        front: device.position == .front),
                    mirrored: Self.mirrorsLikePreview(previewLayer?.connection, front: device.position == .front),
                    on: movieOutput.connection(with: .video))
            }
            if let other = secondaryInput?.device {
                for connection in secondaryConnections where connection.videoPreviewLayer == nil {
                    Self.setFileAngle(
                        CameraOrientation.captureAngle(
                            sideways: sideways, nativePortrait: CameraOrientation.nativePortrait(other),
                            front: other.position == .front),
                        mirrored: Self.mirrorsLikePreview(secondaryConnections.first { $0.videoPreviewLayer != nil }, front: other.position == .front), on: connection)
                }
            }
            #if DEBUG
            let primaryAngle = movieOutput.connection(with: .video)?.videoRotationAngle ?? -1
            Self.diag("[诊断] record start sideways=\(sideways) primary=\(Self.diagName(videoInput?.device))",
                  "fileAngle=\(primaryAngle)",
                  "inset=\(Self.diagName(secondaryInput?.device))",
                  "insetFileAngle=\(secondaryConnections.first { $0.videoPreviewLayer == nil }?.videoRotationAngle ?? -1)")
            #endif
            let dual = !secondaryConnections.isEmpty
                && secondaryOutput.connection(with: .video)?.isActive == true
            Task { @MainActor in
                self.pendingPrimary = nil
                self.pendingSecondary = dual ? nil : .some(nil)
            }
            movieOutput.startRecording(to: url, recordingDelegate: self)
            if dual {
                secondaryOutput.maxRecordedDuration = movieOutput.maxRecordedDuration
                secondaryOutput.startRecording(
                    to: FileManager.default.temporaryDirectory
                        .appendingPathComponent("clip_inset_\(UUID().uuidString).mov"),
                    recordingDelegate: self)
            }
        }
    }

    func stopRecording() {
        guard state == .recording else { return }
        #if DEBUG && targetEnvironment(simulator)
        if Self.isSimulated {
            simulatedTake?.cancel()
            Task { @MainActor in await finishSimulatedTake() }
            return
        }
        #endif
        Self.sessionQueue.async { [movieOutput, secondaryOutput] in
            if movieOutput.isRecording { movieOutput.stopRecording() }
            if secondaryOutput.isRecording { secondaryOutput.stopRecording() }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    @MainActor
    private func finishSimulatedTake() async {
        guard state == .recording, !simulatedFinishing, let started = recordedAt else { return }
        simulatedFinishing = true
        defer { simulatedFinishing = false }
        simulatedTake = nil
        let held = min(max(Date.now.timeIntervalSince(started), 1), simulatedSeconds)
        let url: URL?
        if let sampleTake = await Self.sampleFootageTake(seconds: held) {
            url = sampleTake
        } else {
            url = await DemoClipFactory.makeClip(
                moment: Int.random(in: 1...4),
                label: "Simulator",
                author: nil,
                seconds: held,
                orientation: orientation)
        }
        if let url {
            clipURL = await CameraStyleBaker.bake(
                url, style: cameraStyle, orientation: orientation, recordedAt: started)
        } else {
            clipURL = nil
        }
        state = .ready
    }

    private static func sampleFootageTake(seconds: Double) async -> URL? {
        guard UserDefaults.standard.bool(forKey: "storeShots"),
              let source = Bundle.main.url(forResource: "sample-film", withExtension: "mp4")
        else { return nil }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("simulated-take-\(UUID()).mov")
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0,
              let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else { return nil }
        exporter.outputURL = output
        exporter.outputFileType = .mov
        exporter.timeRange = CMTimeRange(
            start: .zero, duration: CMTime(seconds: min(duration, seconds), preferredTimescale: 600))
        await exporter.export()
        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            return nil
        }
        return output
    }
    #endif

    #if DEBUG
    func acceptDemoClip(_ url: URL) {
        clipURL = url
        recordedAt = .now
    }
    #endif

    func retake() {
        if let clipURL, Self.isTemporary(clipURL) {
            try? FileManager.default.removeItem(at: clipURL)
        }
        clipURL = nil
        recordedAt = nil
        if state != .unavailable { state = .ready }
    }

    private static func isTemporary(_ url: URL) -> Bool {
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(tmp)
    }

    func teardown() {
        let session = self.session
        Self.sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let finishedSuccessfully = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)

        let isPrimary = output === movieOutput
        let camera = connections
            .first { $0.inputPorts.contains { $0.mediaType == .video } }?
            .inputPorts.first { $0.mediaType == .video }?.input as? AVCaptureDeviceInput
        #if DEBUG
        Self.logTakeGeometry(
            outputFileURL, sideways: recordingSideways,
            label: "raw \(isPrimary ? "primary" : "inset") \(Self.diagName(camera?.device))")
        #endif

        Task { @MainActor in
            let file: URL? = finishedSuccessfully ? outputFileURL : nil
            if !finishedSuccessfully {
                try? FileManager.default.removeItem(at: outputFileURL)
            }
            if isPrimary {
                self.pendingPrimary = .some(file)
                self.pendingPrimaryCamera = camera?.device.uniqueID
            } else {
                self.pendingSecondary = .some(file)
                self.pendingSecondaryCamera = camera?.device.uniqueID
            }
            guard case .some(let rawPrimary) = self.pendingPrimary,
                  case .some(let rawSecondary) = self.pendingSecondary
            else { return }
            self.pendingPrimary = nil
            self.pendingSecondary = nil
            let primaryCamera = self.pendingPrimaryCamera
            let secondaryCamera = self.pendingSecondaryCamera

            let wantLandscape = self.recordingSideways
            var learnedSomething = false
            func checked(_ url: URL?, camera: String?) async -> URL? {
                guard let url else { return nil }
                let result = await CameraOrientation.upright(url, landscape: wantLandscape)
                if let camera, let native = result.nativePortrait,
                   CameraOrientation.remember(nativePortrait: native, for: camera) {
                    learnedSomething = true
                }
                return result.url
            }
            let primary = await checked(rawPrimary, camera: primaryCamera)
            let secondary = await checked(rawSecondary, camera: secondaryCamera)
            if learnedSomething { self.applyAngles() }

            guard let primary else {
                if let secondary { try? FileManager.default.removeItem(at: secondary) }
                self.recordedAt = nil
                self.state = .ready
                self.lastFailure = .now
                self.failureCount += 1
                return
            }
            if let secondary,
               let composed = await PiPComposer.compose(
                   primary: primary,
                   secondary: secondary,
                   secondaryIsMain: self.isSwapped,
                   inset: wantLandscape
                       ? PiPComposer.sidewaysRect(self.insetRect)
                       : self.insetRect,
                   aspect: self.cameraStyle.aspectRatio(for: self.orientation)
                       ?? (self.orientation.cropsAfterRecording ? 1 : nil)) {
                self.clipURL = await CameraStyleBaker.bake(
                    composed, style: self.cameraStyle,
                    orientation: self.orientation, recordedAt: self.recordedAt)
                self.state = .ready
                return
            }
            if let secondary { try? FileManager.default.removeItem(at: secondary) }
            let kept = self.orientation.cropsAfterRecording
                ? await SquareCrop.copy(of: primary)
                : primary
            self.clipURL = await CameraStyleBaker.bake(
                kept, style: self.cameraStyle,
                    orientation: self.orientation, recordedAt: self.recordedAt)
            self.state = .ready
        }
    }


    /// Multi-cam format limit. Older phones (iPhone SE) go over the system
    /// pressure budget with two 1080p30 cameras, so dual mode steps down.
    struct CaptureCap: Equatable {
        var width: Int32 = 1920
        var height: Int32 = 1080
        var fps: Int32 = 30
    }

    static let dualCaps: [(main: CaptureCap, other: CaptureCap)] = [
        (CaptureCap(), CaptureCap()),
        (CaptureCap(), CaptureCap(width: 1280, height: 720)),
        (CaptureCap(width: 1280, height: 720), CaptureCap(width: 1280, height: 720)),
        (CaptureCap(width: 1280, height: 720, fps: 24), CaptureCap(width: 1280, height: 720, fps: 24)),
        (CaptureCap(width: 1280, height: 720, fps: 24), CaptureCap(width: 640, height: 480, fps: 24)),
        (CaptureCap(width: 640, height: 480, fps: 24), CaptureCap(width: 640, height: 480, fps: 24)),
    ]

    static func prepare(
        _ device: AVCaptureDevice, for session: AVCaptureSession, cap: CaptureCap = CaptureCap()
    ) -> Bool {
        guard session is AVCaptureMultiCamSession else { return true }
        let formats = device.formats.filter { format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return format.isMultiCamSupported
                && size.width <= cap.width && size.height <= cap.height
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(cap.fps) }
        }
        guard let best = formats.max(by: {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }) else { return true }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: cap.fps)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: cap.fps)
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    func setDualCamera(_ on: Bool) {
        guard state == .ready, clipURL == nil, supportsDualCamera, on != isDualCamera else { return }
        Self.sessionQueue.async { [self] in
            let ok = on ? addSecondaryCamera() : { removeSecondaryCamera(); return true }()
            Task { @MainActor in
                self.isDualCamera = on && ok
                if !self.isDualCamera { self.isSwapped = false }
                self.applyOrientation()
                self.refreshZoom()
                self.applyTorch()
            }
        }
    }

    func attachSecondaryPreview(_ layer: AVCaptureVideoPreviewLayer) {
        Self.sessionQueue.async { [self] in
            secondaryPreviewLayer = layer
            guard let secondaryInput, let port = Self.videoPort(of: secondaryInput),
                  !secondaryConnections.contains(where: { $0.videoPreviewLayer === layer })
            else { return }
            let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: layer)
            session.beginConfiguration()
            if session.canAddConnection(connection) {
                session.addConnection(connection)
                secondaryConnections.append(connection)
            }
            session.commitConfiguration()
            Task { @MainActor in self.applyAngles() }
        }
    }

    private static func videoPort(of input: AVCaptureDeviceInput) -> AVCaptureInput.Port? {
        input.ports(
            for: .video,
            sourceDeviceType: input.device.deviceType,
            sourceDevicePosition: input.device.position
        ).first
    }

    private func addSecondaryCamera() -> Bool {
        guard let multi = session as? AVCaptureMultiCamSession,
              let primary = videoInput else { return false }
        let pairs = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.backCameraTypes + Self.frontCameraTypes,
            mediaType: .video,
            position: .unspecified
        ).supportedMultiCamDeviceSets
        #if DEBUG
        Self.diag("[dual] multicam sets:", pairs.map { $0.map(Self.diagName) })
        #endif

        let backTypes = position == .back
            ? [primary.device.deviceType] + Self.backCameraTypes
            : [.builtInWideAngleCamera] + Self.backCameraTypes
        var chosen: (main: AVCaptureDevice, other: AVCaptureDevice)?
        for type in backTypes {
            guard let back = AVCaptureDevice.default(type, for: .video, position: .back),
                  let front = AVCaptureDevice.default(
                      .builtInWideAngleCamera, for: .video, position: .front),
                  pairs.contains(where: { $0.contains(back) && $0.contains(front) })
            else { continue }
            chosen = position == .back ? (back, front) : (front, back)
            break
        }
        #if DEBUG
        Self.diag("[dual] chosen:", Self.diagName(chosen?.main), Self.diagName(chosen?.other))
        #endif
        guard let chosen, Self.prepare(chosen.main, for: session),
              Self.prepare(chosen.other, for: session),
              let otherInput = try? AVCaptureDeviceInput(device: chosen.other)
        else {
            #if DEBUG
            Self.diag("[dual] fail: no pair / prepare / input")
            #endif
            return false
        }

        session.beginConfiguration()
        if chosen.main != primary.device {
            session.removeInput(primary)
            if let input = try? AVCaptureDeviceInput(device: chosen.main),
               session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
            } else {
                session.addInput(primary)
            }
        }
        guard session.canAddInput(otherInput), session.canAddOutput(secondaryOutput) else {
            #if DEBUG
            Self.diag("[dual] fail: canAddInput", session.canAddInput(otherInput),
                      "canAddOutput", session.canAddOutput(secondaryOutput))
            #endif
            session.commitConfiguration()
            return false
        }
        session.addInputWithNoConnections(otherInput)
        session.addOutputWithNoConnections(secondaryOutput)
        var added: [AVCaptureConnection] = []
        if let port = Self.videoPort(of: otherInput) {
            let toFile = AVCaptureConnection(inputPorts: [port], output: secondaryOutput)
            if session.canAddConnection(toFile) {
                session.addConnection(toFile)
                added.append(toFile)
            }
            if let layer = secondaryPreviewLayer {
                let toPreview = AVCaptureConnection(inputPort: port, videoPreviewLayer: layer)
                if session.canAddConnection(toPreview) {
                    session.addConnection(toPreview)
                    added.append(toPreview)
                }
            }
        }
        session.commitConfiguration()
        #if DEBUG
        Self.diag("[dual] added", added.count, "hardwareCost", multi.hardwareCost,
                  "pressureCost", multi.systemPressureCost,
                  Self.diagName(chosen.main), Self.diagName(chosen.other))
        #endif

        let main = videoInput?.device ?? chosen.main
        var fits = multi.hardwareCost <= 1 && multi.systemPressureCost <= 1
        for cap in Self.dualCaps.dropFirst() where !added.isEmpty && !fits {
            session.beginConfiguration()
            _ = Self.prepare(main, for: session, cap: cap.main)
            _ = Self.prepare(chosen.other, for: session, cap: cap.other)
            session.commitConfiguration()
            fits = multi.hardwareCost <= 1 && multi.systemPressureCost <= 1
            #if DEBUG
            Self.diag("[dual] step down", "hardwareCost", multi.hardwareCost,
                      "pressureCost", multi.systemPressureCost,
                      Self.diagName(main), Self.diagName(chosen.other), "fps", cap.main.fps)
            #endif
        }

        guard !added.isEmpty, fits else {
            secondaryInput = otherInput
            secondaryConnections = added
            removeSecondaryCamera()
            return false
        }
        secondaryInput = otherInput
        secondaryConnections = added
        Task { @MainActor in self.applyAngles() }
        return true
    }

    private func removeSecondaryCamera() {
        session.beginConfiguration()
        for connection in secondaryConnections where session.connections.contains(where: { $0 === connection }) {
            session.removeConnection(connection)
        }
        secondaryConnections = []
        if let secondaryInput { session.removeInput(secondaryInput) }
        secondaryInput = nil
        if session.outputs.contains(secondaryOutput) { session.removeOutput(secondaryOutput) }
        if let current = videoInput { _ = Self.prepare(current.device, for: session) }
        if position == .back, let current = videoInput,
           let widest = camera(for: .back), widest != current.device,
           Self.prepare(widest, for: session) {
            session.removeInput(current)
            if let input = try? AVCaptureDeviceInput(device: widest), session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
            } else {
                session.addInput(current)
            }
        }
        session.commitConfiguration()
    }
}

enum CameraOrientation {
    static let storageKey = "camera.nativePortrait.v1"

    static func nativePortrait(_ device: AVCaptureDevice, defaults: UserDefaults = .standard) -> Bool {
        nativePortrait(uniqueID: device.uniqueID, defaults: defaults)
    }

    static func nativePortrait(uniqueID: String, defaults: UserDefaults = .standard) -> Bool {
        (defaults.dictionary(forKey: storageKey)?[uniqueID] as? Bool) ?? false
    }

    @discardableResult
    static func remember(
        nativePortrait: Bool, for uniqueID: String, defaults: UserDefaults = .standard
    ) -> Bool {
        var known = defaults.dictionary(forKey: storageKey) ?? [:]
        let before = Self.nativePortrait(uniqueID: uniqueID, defaults: defaults)
        known[uniqueID] = nativePortrait
        defaults.set(known, forKey: storageKey)
        return before != nativePortrait
    }

    static func captureAngle(sideways: Bool, nativePortrait: Bool, front: Bool) -> CGFloat {
        let upright: CGFloat = nativePortrait ? 0 : 90
        guard sideways else { return upright }
        let turned = upright + (front ? 90 : -90)
        return (turned + 360).truncatingRemainder(dividingBy: 360)
    }

    static func previewAngle(nativePortrait: Bool) -> CGFloat {
        nativePortrait ? 0 : 90
    }

    static func corrected(
        natural: CGSize, transform: CGAffineTransform, landscape: Bool
    ) -> CGAffineTransform? {
        let shown = CGRect(origin: .zero, size: natural).applying(transform)
        guard natural.width > 0, natural.height > 0,
              (abs(shown.width) > abs(shown.height)) != landscape
        else { return nil }
        let turn: CGFloat = natural.height > natural.width ? -.pi / 2 : .pi / 2
        let linear = CGAffineTransform(
            a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: 0, ty: 0)
        let turned = CGAffineTransform(rotationAngle: turn).concatenating(linear)
        let box = CGRect(origin: .zero, size: natural).applying(turned)
        func snap(_ v: CGFloat) -> CGFloat { abs(v - v.rounded()) < 1e-9 ? v.rounded() : v }
        return CGAffineTransform(
            a: snap(turned.a), b: snap(turned.b), c: snap(turned.c), d: snap(turned.d),
            tx: -box.minX.rounded(), ty: -box.minY.rounded())
    }

    static func upright(_ url: URL, landscape: Bool) async -> (url: URL, nativePortrait: Bool?) {
        let asset = AVURLAsset(url: url)
        guard let video = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await video.load(.naturalSize),
              let transform = try? await video.load(.preferredTransform)
        else { return (url, nil) }
        let native = natural.height > natural.width
        guard let fixed = corrected(natural: natural, transform: transform, landscape: landscape)
        else { return (url, native) }

        let composition = AVMutableComposition()
        guard let duration = try? await asset.load(.duration),
              let videoOut = composition.addMutableTrack(
                  withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return (url, native) }
        let range = CMTimeRange(start: .zero, duration: duration)
        do {
            try videoOut.insertTimeRange(range, of: video, at: .zero)
            if let audio = try await asset.loadTracks(withMediaType: .audio).first,
               let audioOut = composition.addMutableTrack(
                   withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try audioOut.insertTimeRange(range, of: audio, at: .zero)
            }
        } catch {
            return (url, native)
        }
        videoOut.preferredTransform = fixed
        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough)
        else { return (url, native) }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("upright-\(UUID().uuidString).mov")
        export.outputURL = output
        export.outputFileType = .mov
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            return (url, native)
        }
        try? FileManager.default.removeItem(at: url)
        return (output, native)
    }
}

enum PiPComposer {
    static func compose(
        primary: URL, secondary: URL, secondaryIsMain: Bool,
        inset: CGRect = PiPInsetLayout.defaultRect(), aspect: CGFloat?
    ) async -> URL? {
        guard let url = try? await build(
            main: secondaryIsMain ? secondary : primary,
            inset: secondaryIsMain ? primary : secondary,
            audio: primary,
            insetRect: inset,
            aspect: aspect)
        else { return nil }
        try? FileManager.default.removeItem(at: primary)
        try? FileManager.default.removeItem(at: secondary)
        return url
    }

    private static func upright(_ track: AVAssetTrack) async throws -> (CGSize, CGAffineTransform) {
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        return (
            CGSize(width: abs(rect.width), height: abs(rect.height)),
            transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY)))
    }

    private static func even(_ value: CGFloat) -> CGFloat { (value / 2).rounded(.down) * 2 }

    private static func build(
        main: URL, inset: URL, audio: URL, insetRect: CGRect, aspect: CGFloat?
    ) async throws -> URL {
        let mainAsset = AVURLAsset(url: main)
        let insetAsset = AVURLAsset(url: inset)
        let audioAsset = AVURLAsset(url: audio)
        guard let mainTrack = try await mainAsset.loadTracks(withMediaType: .video).first,
              let insetTrack = try await insetAsset.loadTracks(withMediaType: .video).first
        else { throw SquareCrop.CropError.noVideoTrack }

        let duration = CMTimeMinimum(
            try await mainAsset.load(.duration), try await insetAsset.load(.duration))
        let range = CMTimeRange(start: .zero, duration: duration)

        let composition = AVMutableComposition()
        guard let mainOut = composition.addMutableTrack(
                  withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let insetOut = composition.addMutableTrack(
                  withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw SquareCrop.CropError.sessionUnavailable }
        try mainOut.insertTimeRange(range, of: mainTrack, at: .zero)
        try insetOut.insertTimeRange(range, of: insetTrack, at: .zero)
        if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let audioOut = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioOut.insertTimeRange(range, of: audioTrack, at: .zero)
        }

        let (mainSize, mainUpright) = try await upright(mainTrack)
        let (insetSize, insetUpright) = try await upright(insetTrack)
        guard mainSize.width > 0, mainSize.height > 0, insetSize.width > 0, insetSize.height > 0
        else { throw SquareCrop.CropError.noVideoTrack }

        let canvas = canvasSize(main: mainSize, aspect: aspect)

        let mainScale = max(canvas.width / mainSize.width, canvas.height / mainSize.height)
        let mainLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: mainOut)
        mainLayer.setTransform(
            mainUpright
                .concatenating(CGAffineTransform(scaleX: mainScale, y: mainScale))
                .concatenating(CGAffineTransform(
                    translationX: (canvas.width - mainSize.width * mainScale) / 2,
                    y: (canvas.height - mainSize.height * mainScale) / 2)),
            at: .zero)

        let box = pictureBox(insetRect, in: canvas)
        let insetScale = max(box.width / insetSize.width, box.height / insetSize.height)
        let visible = CGRect(
            x: (insetSize.width - box.width / insetScale) / 2,
            y: (insetSize.height - box.height / insetScale) / 2,
            width: box.width / insetScale,
            height: box.height / insetScale)
        let insetLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: insetOut)
        insetLayer.setCropRectangle(
            visible.applying(insetUpright.inverted()).standardized, at: .zero)
        insetLayer.setTransform(
            insetUpright
                .concatenating(CGAffineTransform(translationX: -visible.minX, y: -visible.minY))
                .concatenating(CGAffineTransform(scaleX: insetScale, y: insetScale))
                .concatenating(CGAffineTransform(translationX: box.minX, y: box.minY)),
            at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        instruction.layerInstructions = [insetLayer, mainLayer]

        let video = AVMutableVideoComposition()
        video.renderSize = canvas
        video.frameDuration = CMTime(value: 1, timescale: 30)
        video.instructions = [instruction]
        video.animationTool = frameTool(around: insetRect, canvas: canvas)

        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw SquareCrop.CropError.sessionUnavailable }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("pip-\(UUID().uuidString).mov")
        export.outputURL = output
        export.outputFileType = .mov
        export.videoComposition = video

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw SquareCrop.CropError.failed(export.error?.localizedDescription ?? "unknown")
        }
        return output
    }

    static func sidewaysRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minY, y: 1 - rect.maxX, width: rect.height, height: rect.width)
    }

    static func canvasSize(main: CGSize, aspect: CGFloat?) -> CGSize {
        let full = CGSize(width: even(main.width), height: even(main.height))
        guard let aspect, let cut = CameraStyleBaker.centredCrop(of: full, aspect: aspect)
        else { return full }
        return cut.size
    }

    static func pictureBox(_ rect: CGRect, in canvas: CGSize) -> CGRect {
        let box = PiPInsetLayout.pictureBox(rect, in: canvas)
        return CGRect(
            x: box.minX.rounded(), y: box.minY.rounded(),
            width: even(box.width), height: even(box.height))
    }

    private static func frameTool(
        around rect: CGRect, canvas: CGSize
    ) -> AVVideoCompositionCoreAnimationTool {
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: canvas)
        parent.isGeometryFlipped = true
        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)
        parent.addSublayer(frameLayer(around: rect, canvas: canvas))
        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parent)
    }

    private static func frameLayer(around rect: CGRect, canvas: CGSize) -> CALayer {
        let outer = PiPInsetLayout.box(rect, in: canvas)
        let border = PiPInsetLayout.border(in: canvas)
        let radius = PiPInsetLayout.cornerRadius(in: canvas)
        let path = CGMutablePath()
        path.addRoundedRect(in: outer, cornerWidth: radius, cornerHeight: radius)
        let innerRadius = max(radius - border, 0)
        path.addRoundedRect(
            in: outer.insetBy(dx: border, dy: border),
            cornerWidth: innerRadius, cornerHeight: innerRadius)
        let ring = CAShapeLayer()
        ring.frame = CGRect(origin: .zero, size: canvas)
        ring.path = path
        ring.fillRule = .evenOdd
        ring.fillColor = CGColor(gray: 1, alpha: 1)
        ring.shadowColor = CGColor(gray: 0, alpha: 1)
        ring.shadowOpacity = 0.28
        ring.shadowRadius = border * 2
        ring.shadowOffset = CGSize(width: 0, height: border * 0.75)
        return ring
    }
}

enum SquareCrop {
    static func copy(of url: URL) async -> URL {
        guard let cropped = try? await square(url) else { return url }
        try? FileManager.default.removeItem(at: url)
        return cropped
    }

    private static func square(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first
        else { throw CropError.noVideoTrack }

        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let upright = CGRect(origin: .zero, size: natural).applying(transform)
        let oriented = CGSize(width: abs(upright.width), height: abs(upright.height))
        guard oriented.width > 0, oriented.height > 0 else { throw CropError.noVideoTrack }

        let side = (min(oriented.width, oriented.height) / 2).rounded(.down) * 2
        guard side >= 2 else { throw CropError.noVideoTrack }
        let render = CGSize(width: side, height: side)

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(
            transform
                .concatenating(CGAffineTransform(
                    translationX: -upright.minX, y: -upright.minY))
                .concatenating(CGAffineTransform(
                    translationX: (side - oriented.width) / 2,
                    y: (side - oriented.height) / 2)),
            at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = render
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.instructions = [instruction]

        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else { throw CropError.sessionUnavailable }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("square-\(UUID().uuidString).mov")
        export.outputURL = output
        export.outputFileType = .mov
        export.videoComposition = composition

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw CropError.failed(export.error?.localizedDescription ?? "unknown")
        }
        return output
    }

    enum CropError: LocalizedError {
        case noVideoTrack
        case sessionUnavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "That take has no video to crop."
            case .sessionUnavailable: "The exporter was unavailable."
            case .failed(let reason): "Square crop failed: \(reason)"
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onLayer: (AVCaptureVideoPreviewLayer) -> Void = { _ in }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        onLayer(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

struct SecondaryCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onLayer: (AVCaptureVideoPreviewLayer) -> Void = { _ in }

    func makeUIView(context: Context) -> CameraPreview.PreviewView {
        let view = CameraPreview.PreviewView()
        view.previewLayer.setSessionWithNoConnection(session)
        view.previewLayer.videoGravity = .resizeAspectFill
        onLayer(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: CameraPreview.PreviewView, context: Context) {}
}
