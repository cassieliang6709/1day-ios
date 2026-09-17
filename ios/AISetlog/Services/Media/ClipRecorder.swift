import SwiftUI
import UIKit
import AVFoundation
import Observation

/// Wraps an `AVCaptureSession` for single-take clip capture: live preview,
/// fixed-duration recording (the challenge's clip length), retake, teardown.
@Observable
final class ClipRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    enum State { case idle, ready, recording, unavailable }

    let session = AVCaptureSession()
    private static let sessionQueue = DispatchQueue(label: "com.cassie.AISetlog.capture-session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .front

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    /// The coordinator computes its angles asynchronously — reading them once
    /// straight after `init` yields 0 before it has settled. Observe instead.
    private var captureAngleObservation: NSKeyValueObservation?
    private var previewAngleObservation: NSKeyValueObservation?

    private var isConfigured = false
    /// Recording orientation — locks both the output file and the preview to
    /// upright portrait or landscape. The UI never rotates (the app stays
    /// portrait-locked), only the captured video's frame.
    var orientation: Challenge.Orientation = .portrait {
        didSet { applyOrientation() }
    }

    private(set) var state: State = .idle
    private(set) var clipURL: URL?
    private(set) var recordedAt: Date?

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

    func configure() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            state = .unavailable
            return
        }
        let hasAudioAccess = await AVCaptureDevice.requestAccess(for: .audio)

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
                session.sessionPreset = .high

                guard
                    let camera = camera(for: position),
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
        applyOrientation()
        refreshZoom()
        state = .ready
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
        }
    }

    /// Rebuilds the rotation coordinator for the current device and preview,
    /// then keeps applying its angles as it settles.
    ///
    /// An earlier version hardcoded 90° for any physical camera on the theory
    /// that iPhone sensors are always mounted in landscape. On this device
    /// that over-rotates: the capture pipeline rotates the buffers *and*
    /// writes a 90° preferred transform, so the clip comes out turned a
    /// quarter-turn. `RotationCoordinator` exists to compute this number
    /// correctly per device and camera — use it rather than guessing.
    private func applyOrientation() {
        guard let device = videoInput?.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer)
        rotationCoordinator = coordinator

        // Re-apply whenever the coordinator revises its answer, which it does
        // shortly after creation and whenever the device is physically turned.
        captureAngleObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture, options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.applyAngles() }
        }
        previewAngleObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.applyAngles() }
        }

        applyAngles()
    }

    /// Pushes the coordinator's current angles onto the capture and preview
    /// connections. Safe to call repeatedly — the angles are absolute.
    private func applyAngles() {
        guard let device = videoInput?.device,
              let coordinator = rotationCoordinator else { return }

        let captureAngle = Self.rotationAngle(
            orientation: orientation,
            devicePosition: device.position,
            coordinatedAngle: coordinator.videoRotationAngleForHorizonLevelCapture)
        let captureConnection = movieOutput.connection(with: .video)
        if let connection = captureConnection,
           connection.isVideoRotationAngleSupported(captureAngle) {
            connection.videoRotationAngle = captureAngle
        }

        let previewAngle = Self.rotationAngle(
            orientation: orientation,
            devicePosition: device.position,
            coordinatedAngle: coordinator.videoRotationAngleForHorizonLevelPreview)
        if let connection = previewLayer?.connection,
           connection.isVideoRotationAngleSupported(previewAngle) {
            connection.videoRotationAngle = previewAngle
        }
    }

    /// The angle to put on a connection.
    ///
    /// Both orientations use the coordinator. The app UI is portrait-locked,
    /// but a landscape clip still needs the device/front-camera angle; forcing
    /// 0° leaves the sensor's portrait frame inside the landscape composition.
    /// The coordinator avoids a hard-coded 90° guess.
    static func rotationAngle(
        orientation: Challenge.Orientation,
        devicePosition: AVCaptureDevice.Position,
        coordinatedAngle: CGFloat
    ) -> CGFloat {
        coordinatedAngle
    }

    func flipCamera() {
        guard state == .ready else { return }
        let newPosition: AVCaptureDevice.Position = position == .front ? .back : .front
        session.beginConfiguration()
        if let videoInput { session.removeInput(videoInput) }
        if let camera = camera(for: newPosition),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            position = newPosition
        } else if let videoInput, session.canAddInput(videoInput) {
            session.addInput(videoInput) // revert
        }
        session.commitConfiguration()
        // After the commit, never before: swapping an input rebuilds the
        // session's connections, so an angle set inside the transaction is
        // discarded and the connection falls back to 0° — which records a
        // portrait clip sideways.
        applyOrientation()
        refreshZoom()
    }

    func startRecording(seconds: Double) {
        guard state == .ready else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).mov")
        recordedAt = .now
        state = .recording

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
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    /// Stop early (the "tap to stop" countdown ring) — the delegate fires
    /// exactly as if the max-duration limit had been hit.
    func stopRecording() {
        guard state == .recording else { return }
        Self.sessionQueue.async { [movieOutput] in
            if movieOutput.isRecording { movieOutput.stopRecording() }
        }
    }

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
    func retake() {
        clipURL = nil
        recordedAt = nil
        if state != .unavailable { state = .ready }
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

        Task { @MainActor in
            guard finishedSuccessfully else {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.recordedAt = nil
                self.state = .ready
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
            let kept = self.orientation.cropsAfterRecording
                ? await SquareCrop.copy(of: outputFileURL)
                : outputFileURL
            self.clipURL = kept
            self.state = .ready
        }
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
