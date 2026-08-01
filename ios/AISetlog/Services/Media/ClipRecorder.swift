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

    /// Finds a camera for a position. On a device that's the front/back
    /// wide-angle camera; the iOS 17+ Simulator has no built-in camera, but it
    /// can hand you the host Mac's camera as an external device instead.
    private func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let builtIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return builtIn
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
                    if !session.isRunning { session.startRunning() }
                    continuation.resume(returning: session.isRunning)
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
                session.startRunning()
                continuation.resume(returning: session.isRunning)
            }
        }

        guard configured else {
            state = .unavailable
            return
        }
        applyOrientation()
        state = .ready
    }

    // MARK: - Orientation

    /// Called by `CameraPreview` once its layer exists so the preview's
    /// rotation can be managed here alongside the recorded file's.
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        applyOrientation()
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
    /// Portrait trusts the coordinator, which knows how this specific camera is
    /// mounted. Landscape means "the sensor's own frame", which is 0 — no
    /// rotation, front or back, physical or external.
    static func rotationAngle(
        orientation: Challenge.Orientation,
        devicePosition: AVCaptureDevice.Position,
        coordinatedAngle: CGFloat
    ) -> CGFloat {
        orientation == .portrait ? coordinatedAngle : 0
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
            if finishedSuccessfully {
                self.clipURL = outputFileURL
            } else {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.recordedAt = nil
            }
            self.state = .ready
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
