import SwiftUI
import Observation

/// In-app recorder: live camera only (no library uploads — that's the rule
/// of the game), locked to the challenge's clip length and auto-stops.
///
/// Flow: live preview → record (auto-stop) → looping review → Use / Retake.
///
/// The recorder (`ClipRecorder`) and shared camera UI (`CameraShell`,
/// `MomentStampOverlay`, badges, caption editors) live in `Views/Recording/`.
struct RecordClipView: View {
    let day: Int
    var slotTitle: String?
    var clipLength: Challenge.ClipLength = .tiny
    /// Free-form mode (the camera tab): no cover to dismiss; after review the
    /// clip is filed into a chosen plan instead of a fixed day slot.
    var isFreeform = false
    let onSave: (URL, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var recorder = ClipRecorder()
    @State private var ringProgress: CGFloat = 0
    @State private var overlayText = ""
    @State private var showSavePicker = false
    @State private var toast: String?
    @FocusState private var overlayTextFocused: Bool

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// Whoever's signed in records the clip — solo challenges have no
    /// account, so this (and the identity tint it drives) falls back to a
    /// fixed default.
    private var myName: String? { account.account?.displayName }
    private var myTint: Color { Identity.tint(for: myName) }

    private var clipSeconds: Double { clipLength.seconds }
    private var clipSecondsText: String { clipLength.secondsLabel }
    /// Extra bottom room so the free-form controls clear the floating pill.
    private var bottomInset: CGFloat { isFreeform ? 76 : 18 }
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

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(.bottom, 130)
                }
                .transition(.opacity)
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
                momentTitle: slotTitle ?? Strings.dayN(day),
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
        .padding(.bottom, bottomInset)
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
                    momentTitle: slotTitle ?? Strings.dayN(day),
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
                    Label(Strings.retake, systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.primary)

                Button {
                    if isFreeform {
                        if store.challenges.isEmpty {
                            showToast(Strings.makePlanFirst)
                        } else {
                            showSavePicker = true
                        }
                    } else {
                        onSave(url, trimmedOverlayText)
                        dismiss()
                    }
                } label: {
                    Label(isFreeform ? Strings.fileToPlan : Strings.useClip,
                          systemImage: isFreeform ? "tray.and.arrow.down.fill" : "checkmark")
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
        .padding(.bottom, bottomInset)
        .confirmationDialog(Strings.fileThisClipTo, isPresented: $showSavePicker, titleVisibility: .visible) {
            ForEach(store.challenges) { challenge in
                Button(challenge.title) { file(url, to: challenge) }
            }
        }
    }

    // MARK: - Free-form filing

    /// Free-form: file the clip into a chosen plan's first open slot.
    private func file(_ url: URL, to challenge: Challenge) {
        store.saveClip(from: url, day: targetDay(for: challenge), challengeID: challenge.id, overlayText: trimmedOverlayText)
        recorder.retake()
        ringProgress = 0
        overlayText = ""
        showToast(Strings.filedTo(challenge.title))
    }

    private func targetDay(for challenge: Challenge) -> Int {
        if let open = challenge.cards.first(where: { $0.clipFileName == nil })?.day {
            return open
        }
        return min(max(challenge.currentDay, 1), challenge.cards.count)
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.9))
            if toast == text { withAnimation { toast = nil } }
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 18) {
            topBar
            Spacer()
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(Strings.cameraUnavailable)
                .font(.headline)
            #if DEBUG
            CaptionEditor(text: $overlayText, isFocused: $overlayTextFocused)
            Button(Strings.useDemoClip(slotTitle ?? Strings.dayN(day))) {
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
            Text(Strings.openingCamera)
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
            if isFreeform {
                // No cover to dismiss in the tab — keep the layout balanced.
                Color.clear.frame(width: 52, height: 52)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.92), in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("1DAY")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(myTint)
                Text(slotTitle ?? Strings.dayN(day))
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
            .disabled(recorder.state != .ready || recorder.clipURL != nil)
            .opacity(recorder.state == .ready && recorder.clipURL == nil ? 1 : 0.45)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                recordButton
                Text(Strings.captureState(recording: recorder.state == .recording, secondsLabel: clipSecondsText))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 32))
    }
}
