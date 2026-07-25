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
    /// The challenge's locked frame. Free-form mode ignores this and uses its
    /// own toggleable orientation instead.
    var orientation: Challenge.Orientation = .portrait
    let onSave: (URL, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var recorder = ClipRecorder()
    @State private var ringProgress: CGFloat = 0
    @State private var overlayText = ""
    @State private var showSavePicker = false
    @State private var toast: String?
    @State private var freeformOrientation: Challenge.Orientation = .portrait
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
    private var effectiveOrientation: Challenge.Orientation {
        isFreeform ? freeformOrientation : orientation
    }
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
        .task {
            recorder.orientation = effectiveOrientation
            await recorder.configure()
        }
        .onDisappear { recorder.teardown() }
        .onChange(of: effectiveOrientation) { _, newValue in
            recorder.orientation = newValue
        }
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
                clipSeconds: clipSeconds,
                aspectRatio: effectiveOrientation.aspectRatio
            ) {
                CameraPreview(session: recorder.session) { recorder.attachPreview($0) }
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
                    .fill(myTint)
                    .frame(width: 66, height: 66)
            }
        }
    }

    /// While recording: a big countdown ring (tap to stop early) flanked by
    /// decorative waveform bars.
    private var recordingControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                WaveformBars(tint: myTint)
                countdownRing
                WaveformBars(tint: myTint)
            }
            Text(Strings.tapToStop)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var countdownRing: some View {
        Button {
            recorder.stopRecording()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 5)
                    .frame(width: 84, height: 84)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(myTint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 84, height: 84)
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let elapsed = context.date.timeIntervalSince(recorder.recordedAt ?? context.date)
                    let remaining = max(Int((clipSeconds - elapsed).rounded(.up)), 0)
                    Text("\(remaining)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(myTint)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Review (Use / Retake)

    private func reviewView(_ url: URL) -> some View {
        VStack(spacing: 16) {
            topBar

            CameraShell(
                name: myName,
                momentTitle: slotTitle ?? Strings.dayN(day),
                day: day,
                mode: .review,
                timestamp: recorder.recordedAt,
                overlayText: trimmedOverlayText,
                clipSeconds: clipSeconds,
                aspectRatio: effectiveOrientation.aspectRatio
            ) {
                LoopingClipPlayer(url: url)
            }

            captionBar

            VStack(spacing: 10) {
                Button {
                    if isFreeform {
                        let matches = filingCandidates
                        if store.challenges.isEmpty {
                            showToast(Strings.makePlanFirst)
                        } else if matches.isEmpty {
                            showToast(Strings.noMatchingPlan(landscape: effectiveOrientation == .landscape))
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
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(myTint, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    recorder.retake()
                    ringProgress = 0
                } label: {
                    Label(Strings.retake, systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.systemGray6), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, bottomInset)
        .confirmationDialog(Strings.fileThisClipTo, isPresented: $showSavePicker, titleVisibility: .visible) {
            ForEach(filingCandidates) { challenge in
                Button(challenge.title) { file(url, to: challenge) }
            }
        }
    }

    /// Caption sits below the video (not burned into the frame until save).
    private var captionBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left")
                .font(.headline)
                .foregroundStyle(Color.oneDayBlue)

            TextField(
                "",
                text: $overlayText,
                prompt: Text(Strings.addCaption).foregroundStyle(.secondary)
            )
            .font(.subheadline.weight(.semibold))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($overlayTextFocused)
            .onChange(of: overlayText) { _, newValue in
                if newValue.count > 40 { overlayText = String(newValue.prefix(40)) }
            }

            Image(systemName: "pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.oneDayBlue.opacity(overlayTextFocused ? 0.38 : 0.13), lineWidth: 1.5)
        )
        .shadow(color: Color.oneDayBlue.opacity(0.08), radius: 16, y: 8)
    }

    // MARK: - Free-form filing

    /// Only plans matching the recorded frame can take this clip — a
    /// challenge never mixes portrait and landscape.
    private var filingCandidates: [Challenge] {
        store.challenges.filter { $0.resolvedOrientation == effectiveOrientation }
    }

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
                // No cover to dismiss in the tab — the left slot carries the
                // orientation toggle instead.
                Button {
                    freeformOrientation = freeformOrientation == .portrait ? .landscape : .portrait
                } label: {
                    Image(systemName: freeformOrientation == .portrait
                        ? "rectangle.portrait.rotate" : "rectangle.rotate")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.92), in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.switchOrientation)
                .disabled(recorder.state == .recording || recorder.clipURL != nil)
                .opacity(recorder.state == .recording || recorder.clipURL != nil ? 0.45 : 1)
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
            if recorder.state == .recording {
                recordingControls
            } else {
                VStack(spacing: 10) {
                    recordButton
                    Text(Strings.captureState(recording: false, secondsLabel: clipSecondsText))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 32))
    }
}

/// Decorative symmetric waveform bars flanking the countdown ring while
/// recording — pure ornament, not a live level meter.
private struct WaveformBars: View {
    let tint: Color
    private let heights: [CGFloat] = [4, 9, 14, 7, 12, 18, 8, 5]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(tint.opacity(0.28))
                    .frame(width: 3, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}
