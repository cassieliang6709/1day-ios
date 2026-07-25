import SwiftUI
import UIKit
import AVFoundation
import Observation

/// Wraps an `AVCaptureSession` for single-take clip capture: live preview,
/// fixed-duration recording (the challenge's clip length), retake, teardown.
@Observable
final class ClipRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    enum State { case idle, ready, recording, unavailable }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.cassie.AISetlog.capture-session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .front

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

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
        _ = await AVCaptureDevice.requestAccess(for: .audio)

        let configured = await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                // SwiftUI can preserve this recorder while swapping the clip
                // preview for the re-record screen. Reuse the existing graph
                // instead of trying to add its inputs and output a second time.
                if isConfigured {
                    if !session.isRunning { session.startRunning() }
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

                if let mic = AVCaptureDevice.default(for: .audio),
                   let audioInput = try? AVCaptureDeviceInput(device: mic),
                   session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }

                session.addOutput(movieOutput)
                session.commitConfiguration()
                isConfigured = true
                session.startRunning()
                continuation.resume(returning: true)
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

    /// Lock both the recorded file and the preview to the chosen orientation.
    /// RotationCoordinator accounts for the active camera's native mounting;
    /// this matters in Simulator, whose external Mac camera is already upright
    /// and was previously rotated sideways by the hard-coded 90° angle.
    private func applyOrientation() {
        guard let device = videoInput?.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer)
        rotationCoordinator = coordinator

        let captureAngle = orientation == .portrait
            ? coordinator.videoRotationAngleForHorizonLevelCapture
            : 0
        if let connection = movieOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(captureAngle) {
            connection.videoRotationAngle = captureAngle
        }

        let previewAngle = orientation == .portrait
            ? coordinator.videoRotationAngleForHorizonLevelPreview
            : 0
        if let connection = previewLayer?.connection,
           connection.isVideoRotationAngleSupported(previewAngle) {
            connection.videoRotationAngle = previewAngle
        }
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
            applyOrientation()
        } else if let videoInput, session.canAddInput(videoInput) {
            session.addInput(videoInput) // revert
        }
        session.commitConfiguration()
    }

    func startRecording(seconds: Double) {
        guard state == .ready else { return }
        // The output stops itself at the limit — this enforces the challenge's
        // chosen clip length without adding another decision during recording.
        movieOutput.maxRecordedDuration = CMTime(seconds: seconds, preferredTimescale: 600)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).mov")
        recordedAt = .now
        movieOutput.startRecording(to: url, recordingDelegate: self)
        state = .recording
    }

    /// Stop early (the "tap to stop" countdown ring) — the delegate fires
    /// exactly as if the max-duration limit had been hit.
    func stopRecording() {
        guard state == .recording else { return }
        movieOutput.stopRecording()
    }

    /// Back to live preview after reviewing a take.
    func retake() {
        clipURL = nil
        recordedAt = nil
        if state != .unavailable { state = .ready }
    }

    func teardown() {
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Hitting maxRecordedDuration surfaces as an "error" whose userInfo
        // says the recording finished successfully — treat it as success.
        Task { @MainActor in
            self.clipURL = outputFileURL
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
