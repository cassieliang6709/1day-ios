import SwiftUI
import AVFoundation
import Observation

/// In-app recorder: live camera only (no library uploads — that's the rule
/// of the game), locked to the challenge's clip length and auto-stops.
///
/// Flow: live preview → record (auto-stop) → looping review → Use / Retake.
struct RecordClipView: View {
    let day: Int
    var slotTitle: String?
    var clipLength: Challenge.ClipLength = .tiny
    let onSave: (URL, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account
    @State private var recorder = ClipRecorder()
    @State private var ringProgress: CGFloat = 0
    @State private var overlayText = ""
    @FocusState private var overlayTextFocused: Bool

    /// Whoever's signed in records the clip — solo challenges have no
    /// account, so this (and the identity tint it drives) falls back to a
    /// fixed default.
    private var myName: String? { account.account?.displayName }
    private var myTint: Color { Identity.tint(for: myName) }

    private var clipSeconds: Double { clipLength.seconds }
    private var clipSecondsText: String { clipLength.secondsLabel }
    private var trimmedOverlayText: String? {
        let text = overlayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            CuteCameraBackdrop()

            if let url = recorder.clipURL {
                reviewView(url)
            } else {
                switch recorder.state {
                case .unavailable:
                    unavailableView
                case .idle:
                    loadingView
                default:
                    cameraView
                }
            }
        }
        .task { await recorder.configure() }
        .onDisappear { recorder.teardown() }
        .onChange(of: recorder.state) { _, state in
            if state == .recording {
                ringProgress = 0
                withAnimation(.linear(duration: clipSeconds)) { ringProgress = 1 }
            }
        }
    }

    // MARK: - Camera

    private var cameraView: some View {
        VStack(spacing: 16) {
            topBar

            CameraShell(
                name: myName,
                momentTitle: slotTitle ?? "Day \(day)",
                day: day,
                mode: recorder.state == .recording ? .recording : .live,
                timestamp: recorder.recordedAt,
                overlayText: nil,
                clipSeconds: clipSeconds
            ) {
                CameraPreview(session: recorder.session)
            }

            bottomControls
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var recordButton: some View {
        Button {
            recorder.startRecording(seconds: clipSeconds)
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 5)
                    .frame(width: 84, height: 84)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(myTint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(recorder.state == .recording ? Color(.systemBackground) : myTint)
                    .frame(width: 66, height: 66)
                    .scaleEffect(recorder.state == .recording ? 0.85 : 1)
                    .animation(.spring(duration: 0.3), value: recorder.state == .recording)
                if recorder.state == .recording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(myTint)
                        .frame(width: 26, height: 26)
                }
            }
        }
        .disabled(recorder.state == .recording)
    }

    // MARK: - Review (Use / Retake)

    private func reviewView(_ url: URL) -> some View {
        VStack(spacing: 16) {
            topBar

            ZStack {
                CameraShell(
                    name: myName,
                    momentTitle: slotTitle ?? "Day \(day)",
                    day: day,
                    mode: .review,
                    timestamp: recorder.recordedAt,
                    overlayText: nil,
                    clipSeconds: clipSeconds
                ) {
                    LoopingClipPlayer(url: url)
                }

                CaptionOverlayEditor(text: $overlayText, isFocused: $overlayTextFocused)
            }

            HStack(spacing: 14) {
                Button {
                    recorder.retake()
                    ringProgress = 0
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.primary)

                Button {
                    onSave(url, trimmedOverlayText)
                    dismiss()
                } label: {
                    Label("Use clip", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(myTint)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var unavailableView: some View {
        VStack(spacing: 18) {
            topBar
            Spacer()
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Camera not available")
                .font(.headline)
            #if DEBUG
            CaptionEditor(text: $overlayText, isFocused: $overlayTextFocused)
            Button("Use demo clip for \(slotTitle ?? "Day \(day)")") {
                if let demo = Bundle.main.url(forResource: "day\(day)", withExtension: "mp4") {
                    onSave(demo, trimmedOverlayText)
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(myTint)
            #endif
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var loadingView: some View {
        VStack(spacing: 18) {
            topBar
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(.cyan)
            Text("Opening camera")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.92), in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("1DAY")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(myTint)
                Text(slotTitle ?? "Day \(day)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button { recorder.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.92), in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(recorder.state == .recording || recorder.clipURL != nil)
            .opacity(recorder.clipURL == nil ? 1 : 0.45)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                recordButton
                Text(recorder.state == .recording ? "\(clipSecondsText) capture" : "tap to capture")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 32))
    }
}

private struct CuteCameraBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color.cyan.opacity(0.12),
                Color(.systemBackground),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct CameraShell<Content: View>: View {
    let name: String?
    let momentTitle: String
    let day: Int
    let mode: MomentStampOverlay.Mode
    let timestamp: Date?
    let overlayText: String?
    let clipSeconds: Double
    @ViewBuilder var content: Content

    private var tint: Color { Identity.tint(for: name) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                MomentStampOverlay(
                    name: name,
                    momentTitle: momentTitle,
                    day: day,
                    mode: mode,
                    timestamp: timestamp,
                    overlayText: overlayText,
                    clipSeconds: clipSeconds
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(tint, lineWidth: 3)
            }
            .shadow(color: tint.opacity(0.35), radius: 18, y: 8)
        }
        .aspectRatio(9 / 14.3, contentMode: .fit)
    }
}

struct MomentStampOverlay: View {
    enum Mode {
        case live
        case recording
        case review
    }

    let name: String?
    let momentTitle: String
    let day: Int
    let mode: Mode
    let timestamp: Date?
    var overlayText: String?
    var clipSeconds: Double = 2

    private var stampDate: Date { timestamp ?? .now }

    private var dateText: String {
        stampDate.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var timeText: String {
        stampDate.formatted(date: .omitted, time: .shortened)
    }

    private var modeText: String {
        mode == .recording ? "REC 00:\(String(format: "%02d", Int(clipSeconds)))" : "CAPTURED"
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [.black.opacity(0.22), .clear, .black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack {
                    HStack(alignment: .top) {
                        BrandStamp()
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(dateText)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                            Text(timeText)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.white)
                    }
                    .padding(28)

                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(momentTitle)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                            Text("MOMENT \(day)")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white.opacity(0.78))
                            HStack(spacing: 7) {
                                Capsule()
                                    .fill(.white.opacity(0.42))
                                    .frame(width: 34, height: 5)
                                Capsule()
                                    .fill(.white)
                                    .frame(width: 46, height: 5)
                                Capsule()
                                    .fill(.white.opacity(0.42))
                                    .frame(width: 34, height: 5)
                            }
                        }

                        Spacer()

                        StampBadge(name: name)
                            .frame(width: min(size.width * 0.29, 124), height: min(size.width * 0.29, 124))
                    }
                    .padding(28)
                }

                if mode == .recording {
                    Text(modeText)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.red, in: Capsule())
                        .position(x: size.width * 0.5, y: size.height * 0.5)
                }

                if let overlayText, !overlayText.isEmpty {
                    Text(overlayText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
                        .padding(.horizontal, 38)
                        .position(x: size.width * 0.5, y: size.height * 0.43)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct BrandStamp: View {
    var body: some View {
        HStack(spacing: 9) {
            Text("1D")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(Color.setlogBlue, lineWidth: 3))

            VStack(alignment: .leading, spacing: 1) {
                Text("1DAY")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text("daily film")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
        }
    }
}

/// Whose clip this is, burned into the corner of both the live preview and
/// the final export (`VideoStitcher.addStampDecor` mirrors this look).
private struct StampBadge: View {
    let name: String?

    private var tint: Color { Identity.tint(for: name) }

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .stroke(tint, lineWidth: 5)
            Text(Identity.initial(for: name))
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
    }
}

private struct CaptionOverlayEditor: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        GeometryReader { proxy in
            TextField(
                "",
                text: $text,
                prompt: Text("add a caption")
                    .foregroundStyle(.white.opacity(isFocused.wrappedValue ? 0.32 : 0.42)),
                axis: .vertical
            )
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .tint(Color.setlogCyan)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused(isFocused)
            .textFieldStyle(.plain)
            .lineLimit(1...2)
            .minimumScaleFactor(0.78)
            .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
            .padding(.horizontal, 14)
            .frame(width: proxy.size.width * 0.68, height: 82)
            .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.43)
            .onChange(of: text) { _, newValue in
                if newValue.count > 40 {
                    text = String(newValue.prefix(40))
                }
            }
        }
        .allowsHitTesting(true)
    }
}

private struct CaptionEditor: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat")
                .font(.headline.bold())
                .foregroundStyle(Color.setlogBlue)
                .frame(width: 30, height: 30)
                .background(Color.setlogBlue.opacity(0.12), in: Circle())

            TextField(
                "",
                text: $text,
                prompt: Text("Write on this moment")
                    .foregroundStyle(.secondary)
            )
            .font(.subheadline.weight(.semibold))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused(isFocused)
            .onChange(of: text) { _, newValue in
                if newValue.count > 32 {
                    text = String(newValue.prefix(32))
                }
            }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body.bold())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.86), in: Capsule())
        .overlay(Capsule().stroke(Color.setlogBlue.opacity(0.16), lineWidth: 1))
    }
}

// MARK: - Recorder

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

    func configure() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            state = .unavailable
            return
        }
        _ = await AVCaptureDevice.requestAccess(for: .audio)

        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
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
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
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
