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
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .front

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

        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let camera = camera(for: position),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            state = .unavailable
            return
        }
        session.addInput(input)
        videoInput = input

        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            state = .unavailable
            return
        }
        session.addOutput(movieOutput)
        session.commitConfiguration()

        let session = self.session
        Task.detached { session.startRunning() }
        state = .ready
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

    /// Back to live preview after reviewing a take.
    func retake() {
        clipURL = nil
        recordedAt = nil
        if state != .unavailable { state = .ready }
    }

    func teardown() {
        if session.isRunning {
            let session = self.session
            Task.detached { session.stopRunning() }
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

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
