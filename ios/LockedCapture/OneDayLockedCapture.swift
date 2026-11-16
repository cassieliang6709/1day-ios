import AVFoundation
import LockedCameraCapture
import SwiftUI
import UniformTypeIdentifiers

@main
struct OneDayLockedCapture: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in LockedCaptureView(session: session) }
    }
}

private struct LockedCaptureView: View {
    let session: LockedCameraCaptureSession
    @State private var saved = false
    @State private var saving = false
    @State private var failed = false
    @State private var takeID = UUID()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if saved {
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.yellow)
                    Text(CaptureText.localized("Moment saved", "瞬间已保存")).font(.title2.bold())
                    Button(CaptureText.localized("Continue in 1Day", "在 1Day 中继续")) {
                        Task {
                            do {
                                try await session.openApplication(for: NSUserActivity(
                                    activityType: NSUserActivityTypeLockedCameraCapture))
                            } catch { failed = true }
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                    Button(CaptureText.localized("Film another", "再拍一段")) {
                        takeID = UUID()
                        saved = false
                        failed = false
                    }
                }
                .foregroundStyle(.white)
            } else {
                LockedMoviePicker { url in
                    guard !saving else { return }
                    saving = true
                    Task {
                        defer { saving = false }
                        do {
                            let directory = session.sessionContentURL
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            let destination = directory.appendingPathComponent("\(takeID.uuidString).mov")
                            let pending = directory.appendingPathComponent("\(takeID.uuidString).pending")
                            if FileManager.default.fileExists(atPath: pending.path) {
                                try FileManager.default.removeItem(at: pending)
                            }
                            try FileManager.default.copyItem(at: url, to: pending)
                            if FileManager.default.fileExists(atPath: destination.path) {
                                try FileManager.default.removeItem(at: destination)
                            }
                            try FileManager.default.moveItem(at: pending, to: destination)
                            let asset = AVURLAsset(url: destination)
                            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                                throw CocoaError(.fileReadCorruptFile)
                            }
                            let size = try await track.load(.naturalSize)
                            let transform = try await track.load(.preferredTransform)
                            let oriented = size.applying(transform)
                            let duration = try await asset.load(.duration).seconds
                            guard duration.isFinite, duration > 0, duration <= 2.5 else {
                                throw CocoaError(.fileReadCorruptFile)
                            }
                            let manifest = LockedCaptureManifest(
                                id: takeID, recordedAt: .now.addingTimeInterval(-duration),
                                landscape: abs(oriented.width) > abs(oriented.height))
                            try JSONEncoder().encode(manifest).write(
                                to: directory.appendingPathComponent(manifest.manifestName), options: .atomic)
                            saved = true
                            failed = false
                        } catch { failed = true }
                    }
                }
                .id(takeID)
                .ignoresSafeArea()
                .disabled(saving)
            }
            if saving { ProgressView().tint(.white) }
            if failed {
                VStack {
                    Spacer()
                    Text(CaptureText.localized(
                        "Couldn't finish. Your saved moments are kept. Try again.",
                        "未能完成，已保存的片段仍在。请重试。"))
                        .padding().background(.black.opacity(0.8)).foregroundStyle(.white)
                }
            }
        }
    }
}

private struct LockedMoviePicker: UIViewControllerRepresentable {
    let onCapture: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = 2
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (URL) -> Void
        init(onCapture: @escaping (URL) -> Void) { self.onCapture = onCapture }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let url = info[.mediaURL] as? URL else { return }
            onCapture(url)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.cameraCaptureMode = .video
        }
    }
}
