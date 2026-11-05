import SwiftUI
import UIKit
import AVFoundation
import Observation

/// Wraps an `AVCaptureSession` for single-take clip capture: live preview,
/// fixed-duration recording (the challenge's clip length), retake, teardown.
@Observable
final class ClipRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    enum State { case idle, ready, recording, unavailable }

    /// A multi-cam session on phones that have one, so the front camera can
    /// be added next to the back one without rebuilding the session. Single
    /// camera filming goes through it exactly as through a plain session.
    let session: AVCaptureSession = AVCaptureMultiCamSession.isMultiCamSupported
        ? AVCaptureMultiCamSession()
        : AVCaptureSession()
    private static let sessionQueue = DispatchQueue(label: "com.cassie.AISetlog.capture-session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    /// Re-applies the fixed angles whenever the session rebuilds its
    /// connections. Switching camera, adding the second one or restarting the
    /// session replaces them some time after `commitConfiguration`, and a new
    /// connection starts at 0° — a portrait take filmed sideways. The angle
    /// set straight after the commit doesn't survive that.
    @ObservationIgnored private var connectionObservers: [NSObjectProtocol] = []

    // MARK: Dual camera (picture in picture)
    //
    // The second camera gets its own input, movie output and preview layer,
    // wired with explicit connections so nothing auto-connects across the two.
    // Each take writes two files; `PiPComposer` folds them into the one clip
    // everything after the camera already expects.
    private let secondaryOutput = AVCaptureMovieFileOutput()
    private var secondaryInput: AVCaptureDeviceInput?
    private var secondaryConnections: [AVCaptureConnection] = []
    private weak var secondaryPreviewLayer: AVCaptureVideoPreviewLayer?

    /// Both cameras are filming: the main camera full frame, the other one in
    /// the corner inset.
    private(set) var isDualCamera = false
    /// In dual mode, true when the secondary camera is the big picture. Flip
    /// toggles this instead of swapping inputs.
    private(set) var isSwapped = false
    /// Where the inset sits, normalized to the frame (see `PiPInsetLayout`).
    /// Dragged and pinched on the viewfinder, read by `PiPComposer` when the
    /// take is folded into one file, and kept across launches — the spot you
    /// picked is the spot you want next time.
    var insetRect: CGRect = PiPInsetLayout.load() {
        didSet { PiPInsetLayout.save(insetRect) }
    }
    /// Files of the take in flight, collected as each output finishes.
    private var pendingPrimary: URL??
    /// Which camera made each file of the take in flight, by `uniqueID`, so
    /// the shape it came out in can be learned — see `CameraOrientation`.
    private var pendingPrimaryCamera: String?
    private var pendingSecondaryCamera: String?
    /// Whether the take in flight is 横拍, as it was when it started.
    private var recordingSideways = false
    private var pendingSecondary: URL??

    /// Whether this phone can film both cameras at once.
    var supportsDualCamera: Bool {
        session is AVCaptureMultiCamSession && !Self.isSimulated
    }

    private var isConfigured = false
    /// Recording orientation — locks both the output file and the preview to
    /// upright portrait or landscape. The UI never rotates (the app stays
    /// portrait-locked), only the captured video's frame.
    var orientation: Challenge.Orientation = .portrait {
        didSet { applyOrientation() }
    }
    /// 横拍: film as if the phone is held sideways (top to the left), whatever
    /// the tilt reads. Only this switch decides the angle — see `captureAngle`.
    var forcedLandscape = false {
        didSet { applyAngles() }
    }
    /// The camera picked in the viewfinder. Baked into each take as it lands —
    /// see `CameraStyleBaker`.
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

    /// Bumped each time a take fails to reach a file. A counter rather than a
    /// Bool so two failures in a row still read as two changes to whoever is
    /// watching it — the camera turns each one into a toast and a haptic. The
    /// failure path used to go straight back to `.ready`, which on screen is
    /// indistinguishable from "the press didn't register".
    private(set) var failureCount = 0
    /// When the latest failure happened; nil until there has been one.
    private(set) var lastFailure: Date?

    /// Whether the microphone was granted at the last `configure()`. Without
    /// it the session films silently, and nothing about a silent preview says
    /// so — the camera reads this to put up a "no sound" chip.
    private(set) var hasAudioAccess = true

    /// What the current lens can reach, and where it is pointed now — both in
    /// display values (0.5, 1, 2), never in `videoZoomFactor`. See `CameraZoom`.
    private(set) var zoomCapabilities: CameraZoom = .unavailable
    private(set) var zoom: CGFloat = 1

    /// The chips to draw. One entry means this camera has no zoom worth
    /// offering, and the UI draws nothing.
    var zoomPresets: [CGFloat] { zoomCapabilities.presets() }

    /// Lens preference for the back camera, widest reach first.
    ///
    /// A *virtual* device is what makes 0.5x exist at all: it spans the
    /// ultra-wide, wide and telephoto lenses and hands over between them as
    /// the zoom factor crosses their switch-over points, so the session sees
    /// one input and the person gets three lenses. Asking for
    /// `.builtInWideAngleCamera` — which is what this used to do — gets one
    /// lens and a hard floor of 1x no matter what the phone has in it.
    private static let backCameraTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera,
        .builtInDualWideCamera,
        .builtInDualCamera,
        .builtInWideAngleCamera,
    ]

    /// The front camera is a single lens on every phone — no ultra-wide to
    /// reach for, so nothing virtual to ask for either.
    private static let frontCameraTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]

    /// Finds a camera for a position: the widest-reaching virtual device the
    /// phone has, falling back through to a single wide-angle lens. The iOS 17+
    /// Simulator has no built-in camera, but it can hand you the host Mac's
    /// camera as an external device instead.
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
    /// A camera for screenshots on the simulator, which has none: launch with
    /// `-simulatedCamera YES`. The preview is `SimulatedCameraPreview` and a
    /// take is a `DemoClipFactory` clip, delivered through the same state
    /// changes a real take goes through. Opt-in, so UI tests still get the
    /// 相机不可用 screen and its 示例片段 button.
    static var isSimulated: Bool {
        UserDefaults.standard.bool(forKey: "simulatedCamera")
    }
    private var simulatedTake: Task<Void, Never>?
    private var simulatedSeconds: Double = 0
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
                // SwiftUI can preserve this recorder while swapping the clip
                // preview for the re-record screen. Reuse the existing graph
                // instead of trying to add its inputs and output a second time.
                if isConfigured {
                    // The preview layer may not exist yet. Starting here can
                    // leave the first camera page showing a black frame.
                    continuation.resume(returning: true)
                    return
                }

                session.beginConfiguration()
                // A multi-cam session takes formats per device, not a preset.
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
                // Start after `CameraPreview` attaches its layer. This avoids
                // racing the first frame against SwiftUI view creation.
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

    // MARK: - Torch (闪光灯)

    /// 闪光灯 on the camera screen. Video has no flash, so this is the back
    /// camera's light held on for as long as it's switched on — through the
    /// preview and the take alike, which is what you want when the room is
    /// dark. Kept while you flip to the front camera (which has no light) and
    /// lit again when you flip back.
    private(set) var isTorchOn = false

    /// Whether the camera on screen now has a light to turn on. The front
    /// camera has none; in dual mode the back one still does.
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

    /// Sets the light to match `isTorchOn`. Called after anything that swaps
    /// an input or starts the session, because a new input comes up dark.
    private func applyTorch() {
        guard let device = torchDevice else { return }
        let on = isTorchOn
        // Same queue as zoom and session setup: `lockForConfiguration` blocks.
        Self.sessionQueue.async {
            do { try device.lockForConfiguration() } catch { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    // MARK: - Zoom

    /// Point the lens at a display zoom value — 0.5, 1, 2, or anything in
    /// between and above that this camera can reach.
    ///
    /// Clamped here rather than by the caller, so a pinch can hand over a raw
    /// running product and a slider can hand over its own bounds without
    /// either of them knowing what lenses are behind the preview.
    func setZoom(_ display: CGFloat) {
        guard let device = videoInput?.device else { return }
        let clamped = zoomCapabilities.clampedDisplay(display)
        zoom = clamped

        let factor = zoomCapabilities.factor(forDisplay: clamped)
        // Same queue as session setup and teardown: `lockForConfiguration`
        // blocks, and a pinch runs it on every gesture frame.
        Self.sessionQueue.async {
            do {
                try device.lockForConfiguration()
            } catch {
                return
            }
            // The device's own limits, not the UI's: `CameraZoom` caps the
            // interactive range well below the hardware's, and setting a
            // factor outside the real range raises.
            device.videoZoomFactor = min(
                max(factor, device.minAvailableVideoZoomFactor),
                device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        }
    }

    /// Re-reads the lens's zoom range and parks at 1x. Called on every input
    /// change, because a different lens is a different range.
    ///
    /// 1x rather than keeping the number: the front camera's range has no
    /// 0.5x in it, so carrying a display value across a flip would either
    /// clamp to a picture the chips no longer describe or leave a 10x crop on
    /// a lens with no optical reach to hide it.
    private func refreshZoom() {
        guard let device = videoInput?.device else {
            zoomCapabilities = .unavailable
            zoom = 1
            return
        }
        zoomCapabilities = CameraZoom(device: device)
        setZoom(1)
    }

    // MARK: - Orientation

    /// Called by `CameraPreview` once its layer exists so the preview's
    /// rotation can be managed here alongside the recorded file's.
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        applyOrientation()
        Self.sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            // A torch only lights on a running session.
            Task { @MainActor in self.applyTorch() }
        }
    }

    /// Puts the fixed angles back on every connection; the device or the
    /// preview may be new.
    private func applyOrientation() {
        applyAngles()
    }

    /// Pushes the fixed angles onto the capture and preview connections of
    /// both cameras. Safe to call repeatedly — the angles are absolute.
    ///
    /// How the phone is held is not read at all: 竖拍 and 横拍 each have one
    /// angle per camera, and only the 横拍 switch picks between them. The
    /// angle depends on which way that camera's sensor hands its frames over
    /// — see `CameraOrientation`; one number for every camera filmed the
    /// iPhone 17 front camera a quarter-turn off.
    ///
    /// Runs on the session queue, the one that adds and removes connections.
    /// Set from the main thread, an angle could land on a connection the
    /// queue was tearing down, and AVFoundation threw (NSRangeException,
    /// "Cannot remove an observer … for the key path enabled").
    private func applyAngles() {
        let sideways = forcedLandscape
        Self.sessionQueue.async { [self] in
            guard let device = videoInput?.device else { return }
            let native = CameraOrientation.nativePortrait(device)
            Self.setFileAngle(
                CameraOrientation.captureAngle(
                    sideways: sideways, nativePortrait: native, front: device.position == .front),
                mirrored: device.position == .front,
                on: movieOutput.connection(with: .video))
            // The viewfinder stays upright on the portrait-locked screen even
            // in 横拍: the phone itself is turned, so the live picture already
            // reads upright in the hand. Only the file is filmed sideways.
            Self.setAngle(
                CameraOrientation.previewAngle(nativePortrait: native),
                on: previewLayer?.connection)

            if let other = secondaryInput?.device {
                let otherNative = CameraOrientation.nativePortrait(other)
                for connection in secondaryConnections {
                    if connection.videoPreviewLayer == nil {
                        // The inset's selfie is filmed mirrored too, the way
                        // its preview shows it — as the single front camera's is.
                        Self.setFileAngle(
                            CameraOrientation.captureAngle(
                                sideways: sideways, nativePortrait: otherNative,
                                front: other.position == .front),
                            mirrored: other.position == .front, on: connection)
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
    /// 诊断: printed and flushed at once — piped to `devicectl --console`,
    /// stdout is buffered and the lines only arrived when the app quit.
    nonisolated static func diag(_ items: Any...) {
        print(items.map { "\($0)" }.joined(separator: " "))
        fflush(stdout)
    }

    /// 诊断: which camera, and the shape its sensor hands over before rotation.
    nonisolated static func diagName(_ device: AVCaptureDevice?) -> String {
        guard let device else { return "none" }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let side = device.position == .front ? "front" : "back"
        return "\(side)/\(device.deviceType.rawValue.split(separator: ".").last ?? "")/format=\(dims.width)x\(dims.height)"
            + "/nativePortrait=\(CameraOrientation.nativePortrait(device))"
    }

    /// 诊断: what each connection reads back after the angles went on.
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
    /// Prints what a take actually is on disk, to check 横拍 lands landscape.
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
        // Both cameras are already on: flipping means trading places.
        if isDualCamera {
            isSwapped.toggle()
            return
        }
        let newPosition: AVCaptureDevice.Position = position == .front ? .back : .front
        // On the session queue with every other change to the session's
        // inputs and connections, so an angle being set can't meet a
        // connection being torn down. `sync`: the rest of this needs the new
        // input, and nothing on that queue waits for the main thread.
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
                session.addInput(videoInput) // revert
            }
            session.commitConfiguration()
        }
        // After the commit, never before: swapping an input rebuilds the
        // session's connections, so an angle set inside the transaction is
        // discarded and the connection falls back to 0° — which records a
        // portrait clip sideways.
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

        // Keep capture operations serialized with session startup/teardown.
        // A re-record can arrive while the previous session is still releasing
        // the camera; restart here before asking the movie output to record.
        Self.sessionQueue.async { [self] in
            if !session.isRunning { session.startRunning() }
            guard session.isRunning else {
                Task { @MainActor in
                    self.recordedAt = nil
                    self.state = .unavailable
                }
                return
            }

            movieOutput.maxRecordedDuration = CMTime(
                seconds: seconds,
                preferredTimescale: 600)
            // Last word on the file's angle, on the queue that records: a
            // connection rebuilt since the viewfinder was set would otherwise
            // film at 0°.
            if let device = videoInput?.device {
                Self.setFileAngle(
                    CameraOrientation.captureAngle(
                        sideways: sideways, nativePortrait: CameraOrientation.nativePortrait(device),
                        front: device.position == .front),
                    mirrored: device.position == .front,
                    on: movieOutput.connection(with: .video))
            }
            if let other = secondaryInput?.device {
                for connection in secondaryConnections where connection.videoPreviewLayer == nil {
                    Self.setFileAngle(
                        CameraOrientation.captureAngle(
                            sideways: sideways, nativePortrait: CameraOrientation.nativePortrait(other),
                            front: other.position == .front),
                        mirrored: other.position == .front, on: connection)
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

    /// Stop early (the "tap to stop" countdown ring) — the delegate fires
    /// exactly as if the max-duration limit had been hit.
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
    /// What the movie output's delegate does at the end of a real take: the
    /// clip lands, then `.ready`. Length is how long the shutter was held.
    @MainActor
    private func finishSimulatedTake() async {
        guard state == .recording, let started = recordedAt else { return }
        simulatedTake = nil
        let held = min(max(Date.now.timeIntervalSince(started), 1), simulatedSeconds)
        // `-storeShots YES` shows the sample footage in the viewfinder, so the
        // take is cut from that too; a green test card after a real-looking
        // preview would end up in every screenshot of 我的.
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

    /// The first `seconds` of the bundled sample film, or nil outside
    /// `-storeShots` or when the cut fails (the caller falls back to the card).
    private static func sampleFootageTake(seconds: Double) async -> URL? {
        guard UserDefaults.standard.bool(forKey: "storeShots"),
              let source = Bundle.main.url(forResource: "sample-film", withExtension: "mp4")
        else { return nil }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("simulated-take-\(UUID()).mov")
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0,
              // Passthrough: `CameraStyleBaker` re-encodes right after, so a
              // second encode here only doubled the wait after the shutter.
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
    /// Drop a generated clip in as if it had just been filmed, so the review
    /// screen and everything downstream of it can be exercised on a simulator,
    /// which has no camera.
    func acceptDemoClip(_ url: URL) {
        clipURL = url
        recordedAt = .now
    }
    #endif

    /// Back to live preview after reviewing a take.
    ///
    /// Deletes the take's file when it is still in the temp directory. Every
    /// caller that keeps the take — filing (`ClipFileStore.storeClip`) and
    /// drafts (`ClipDraftStore.keep`) — copies synchronously *before* calling
    /// this, so by now the temp file is a leftover; without this each retake
    /// left a .mov behind until the OS got round to purging tmp. Anything
    /// outside tmp is somebody else's file and is never touched.
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
            // Wait for both outputs of a dual take before doing anything.
            guard case .some(let rawPrimary) = self.pendingPrimary,
                  case .some(let rawSecondary) = self.pendingSecondary
            else { return }
            self.pendingPrimary = nil
            self.pendingSecondary = nil
            let primaryCamera = self.pendingPrimaryCamera
            let secondaryCamera = self.pendingSecondaryCamera

            // Every file leaves here the shape the switch asked for: 横拍
            // landscape, otherwise upright. A camera met for the first time,
            // or one whose sensor turned out the other way round, is turned
            // right here and remembered, so its next take is filmed right.
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
            // The crop happens here rather than on the way out of the review
            // screen, so `clipURL` is the only thing anybody downstream — the
            // review player, the draft store, the uploader, the stitcher —
            // ever sees, and none of them has to ask what shape it is.
            //
            // `state` stays `.recording` while it runs. Going `.ready` with no
            // clip yet puts the live preview and a live shutter back for the
            // half second the export takes, which invites a second take over
            // the top of the one being written.
            //
            // A dual take that cannot be composed falls back to the main
            // camera's file alone: still the take, just without the inset.
            if let secondary,
               let composed = await PiPComposer.compose(
                   primary: primary,
                   secondary: secondary,
                   secondaryIsMain: self.isSwapped,
                   // 横拍: the viewfinder is upright on the screen, but the
                   // phone is held sideways and the file is landscape, so
                   // the inset's place turns with it.
                   inset: wantLandscape
                       ? PiPComposer.sidewaysRect(self.insetRect)
                       : self.insetRect,
                   // The shape the viewfinder showed: the camera style's
                   // frame, else square or the full picture. Composed at
                   // the full picture and cropped after, the inset moved
                   // and changed shape from where it was placed.
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

    // MARK: - Dual camera

    /// Puts the device on a 1080p, 30 fps format a multi-cam session can run.
    /// A plain session uses its `.high` preset instead, so this does nothing
    /// there. Returns false only when the device cannot be configured at all.
    static func prepare(_ device: AVCaptureDevice, for session: AVCaptureSession) -> Bool {
        guard session is AVCaptureMultiCamSession else { return true }
        let formats = device.formats.filter { format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return format.isMultiCamSupported
                && size.width <= 1920 && size.height <= 1080
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }
        guard let best = formats.max(by: {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }) else { return true }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    /// Turns the second camera on or off. Ignored mid-take and on phones that
    /// cannot run two cameras; if the hardware refuses the pair, the camera
    /// stays single and `isDualCamera` stays false.
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

    /// Called by the inset's preview view once its layer exists.
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

    /// The opposite camera, plus — when the phone cannot pair it with the
    /// current back lens set — a back lens it can pair with. Runs on the
    /// session queue.
    private func addSecondaryCamera() -> Bool {
        guard let multi = session as? AVCaptureMultiCamSession,
              let primary = videoInput else { return false }
        let pairs = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.backCameraTypes + Self.frontCameraTypes,
            mediaType: .video,
            position: .unspecified
        ).supportedMultiCamDeviceSets

        // Keep the current lens if it pairs; otherwise step down the back
        // lens list until one does.
        // From the front camera, the single wide lens first: a virtual back
        // device (triple / dual) has no one video port to wire into the
        // inset, so the pair came up empty and dual mode silently failed.
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
        guard let chosen, Self.prepare(chosen.main, for: session),
              Self.prepare(chosen.other, for: session),
              let otherInput = try? AVCaptureDeviceInput(device: chosen.other)
        else { return false }

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

        // Two cameras at 1080p can still be over the phone's budget.
        guard !added.isEmpty, multi.hardwareCost <= 1, multi.systemPressureCost <= 1 else {
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

    /// Runs on the session queue.
    private func removeSecondaryCamera() {
        session.beginConfiguration()
        for connection in secondaryConnections { session.removeConnection(connection) }
        secondaryConnections = []
        if let secondaryInput { session.removeInput(secondaryInput) }
        secondaryInput = nil
        if session.outputs.contains(secondaryOutput) { session.removeOutput(secondaryOutput) }
        // Back to the widest back lens, so 0.5x is there again.
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

/// Which way each camera's sensor hands its frames over, and the fixed
/// angles that follow from it.
///
/// `videoRotationAngle` turns whatever the sensor delivers. The back cameras
/// deliver landscape frames (1920×1080), so 竖拍 is 90° and 横拍 0°. The
/// iPhone 17 front camera delivers portrait ones (1080×1920) while its format
/// still says 1920×1080, so the same 90° filmed every selfie sideways —
/// measured on Cassie's iPhone 17 Pro Max, 2026-10-27. Older front cameras
/// are landscape like the back ones.
///
/// Nothing in the format tells the two apart, so each camera's answer is
/// learned from its first take — the file's natural size is the sensor's
/// shape, whatever angle was set — kept per device, and that first take is
/// turned upright by `upright` on the way out. Unknown means landscape.
enum CameraOrientation {
    static let storageKey = "camera.nativePortrait.v1"

    static func nativePortrait(_ device: AVCaptureDevice, defaults: UserDefaults = .standard) -> Bool {
        nativePortrait(uniqueID: device.uniqueID, defaults: defaults)
    }

    static func nativePortrait(uniqueID: String, defaults: UserDefaults = .standard) -> Bool {
        (defaults.dictionary(forKey: storageKey)?[uniqueID] as? Bool) ?? false
    }

    /// Stores what a take showed. True when it changes what was known.
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

    /// The file's angle. 竖拍: a landscape sensor turns a quarter, a portrait
    /// one is already upright. 横拍 (phone top to the left) turns a quarter
    /// from there — back the other way for the front camera, which faces the
    /// other way: the back camera ends at 0°, the front one at 180° (landscape
    /// sensor) or 90° (portrait sensor). 270° filmed the iPhone 17's 横拍
    /// selfies upside down.
    static func captureAngle(sideways: Bool, nativePortrait: Bool, front: Bool) -> CGFloat {
        let upright: CGFloat = nativePortrait ? 0 : 90
        guard sideways else { return upright }
        let turned = upright + (front ? 90 : -90)
        return (turned + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The viewfinder's angle: upright on the portrait-locked screen, in
    /// 竖拍 and 横拍 alike.
    static func previewAngle(nativePortrait: Bool) -> CGFloat {
        nativePortrait ? 0 : 90
    }

    /// The take's transform turned a quarter so it shows `landscape` (or
    /// upright), or nil when it already does. A wrong shape means the
    /// sensor was guessed the other way round, and the angle set was a
    /// quarter-turn off in a known direction: a portrait sensor needed 90°
    /// less than a landscape one. The turn goes on before the existing
    /// transform, so a selfie's mirroring stays as it was.
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
        // Snap: `rotationAngle` leaves 1e-17 where a 0 belongs.
        func snap(_ v: CGFloat) -> CGFloat { abs(v - v.rounded()) < 1e-9 ? v.rounded() : v }
        return CGAffineTransform(
            a: snap(turned.a), b: snap(turned.b), c: snap(turned.c), d: snap(turned.d),
            tx: -box.minX.rounded(), ty: -box.minY.rounded())
    }

    /// `url` the shape asked for — re-muxed with a corrected transform when
    /// it isn't, no re-encode — plus the sensor's shape it revealed (nil when
    /// the file couldn't be read). On any failure the take is kept as it was.
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

/// Folds a dual-camera take — two files, one per camera — into one clip: the
/// main camera fills the frame, the other sits in a white-bordered inset
/// wherever it was placed on the viewfinder (`PiPInsetLayout`).
///
/// Same reasoning as `SquareCrop`: done once, straight after the take, so
/// every reader of `clipURL` still sees one ordinary file. The audio comes
/// from the primary file, which is the only one with a microphone connected.
enum PiPComposer {
    /// The composed clip, or nil on any failure (inputs left in place for
    /// the caller's fallback). Deletes both inputs on success. `inset` is the
    /// normalized rect from the viewfinder.
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

    /// Upright frame size, and the transform that puts the stored frame
    /// upright at the origin.
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

        // Main: aspect-fill the canvas, centred.
        let mainScale = max(canvas.width / mainSize.width, canvas.height / mainSize.height)
        let mainLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: mainOut)
        mainLayer.setTransform(
            mainUpright
                .concatenating(CGAffineTransform(scaleX: mainScale, y: mainScale))
                .concatenating(CGAffineTransform(
                    translationX: (canvas.width - mainSize.width * mainScale) / 2,
                    y: (canvas.height - mainSize.height * mainScale) / 2)),
            at: .zero)

        // Inset: same shape as the canvas, where it was placed, aspect-filled
        // and cropped to the picture box inside the white border so it does
        // not spill over the main picture.
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
        // First is on top.
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

    /// The inset's place in a 横拍 file, from where it sat on the viewfinder.
    /// The viewfinder is upright on the portrait screen while the phone is
    /// held top to the left, so the screen's x runs up the world and its y
    /// runs right: what sat at the screen's top right sits at the file's top
    /// left. Width and height are the same share, so only the corner moves.
    static func sidewaysRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minY, y: 1 - rect.maxX, width: rect.height, height: rect.width)
    }

    /// The composed frame: the main picture cut to `aspect` (width / height)
    /// around its centre, the shape the viewfinder showed. The inset rect is
    /// a share of that shape, so the file has to be that shape too — a crop
    /// after composing moves the inset and changes its shape.
    static func canvasSize(main: CGSize, aspect: CGFloat?) -> CGSize {
        let full = CGSize(width: even(main.width), height: even(main.height))
        guard let aspect, let cut = CameraStyleBaker.centredCrop(of: full, aspect: aspect)
        else { return full }
        return cut.size
    }

    /// The picture box on the file's canvas, snapped to whole even pixels.
    static func pictureBox(_ rect: CGRect, in canvas: CGSize) -> CGRect {
        let box = PiPInsetLayout.pictureBox(rect, in: canvas)
        return CGRect(
            x: box.minX.rounded(), y: box.minY.rounded(),
            width: even(box.width), height: even(box.height))
    }

    /// The white rounded frame burned over the inset, so the file has the
    /// same snapshot border the viewfinder draws.
    ///
    /// A ring — the outer rounded rect minus the inner one, even-odd — laid
    /// over the video. The picture under it is a plain rectangle; the ring
    /// covers its square corners because the inner radius is kept small
    /// enough (see `PiPInsetLayout.cornerShare`). The soft shadow falls
    /// outward onto the main picture, as the viewfinder's does.
    private static func frameTool(
        around rect: CGRect, canvas: CGSize
    ) -> AVVideoCompositionCoreAnimationTool {
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: canvas)
        // Top-left origin, to match the rect's coordinates.
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

/// Turns a recorded take into a square one.
///
/// The camera cannot film a square: `AVCaptureMovieFileOutput` takes a rotation
/// angle and nothing else, so the file it writes is always the sensor's whole
/// frame. A square room therefore films upright and centre-crops immediately
/// afterwards, and the cropped file is the only one that survives.
///
/// Cropping here rather than at export time means it happens once, to one clip,
/// while the person is still looking at the review screen — and the stitcher
/// then reads `sourceAspect` 1 off the file and builds a square canvas by the
/// rules it already has, with no crop of its own.
enum SquareCrop {
    /// A square copy, or the original URL when there is nothing to gain.
    ///
    /// Returns the input on any failure. A take that could not be cropped is
    /// still the take somebody just filmed: it goes to the review screen in the
    /// shape it came out of the camera, which is worse than square and far
    /// better than gone.
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
        // The frame as a viewer sees it, which is what has to end up square —
        // a 1080×1920 file and a 1920×1080 file carrying a quarter turn are the
        // same upright take, and cropping the stored dimensions would take the
        // square out of the wrong axis on one of them.
        let upright = CGRect(origin: .zero, size: natural).applying(transform)
        let oriented = CGSize(width: abs(upright.width), height: abs(upright.height))
        guard oriented.width > 0, oriented.height > 0 else { throw CropError.noVideoTrack }

        // H.264 wants even dimensions.
        let side = (min(oriented.width, oriented.height) / 2).rounded(.down) * 2
        guard side >= 2 else { throw CropError.noVideoTrack }
        let render = CGSize(width: side, height: side)

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        // Rotate upright, pull the rotated frame back to the origin, then slide
        // the middle of it under the square. Two of the four rotations leave
        // the extent in negative space, which is what `upright.minX/minY`
        // absorbs — without it the take lands off-canvas and exports black.
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

/// The inset's live picture. A no-connection layer: the recorder wires it to
/// the second camera itself, so it never picks up the main camera.
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
