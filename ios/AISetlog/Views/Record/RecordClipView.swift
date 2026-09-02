import SwiftUI
import Observation
import AVFoundation

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
    var showsPrompt = true
    /// Free-form mode (the camera tab): no cover to dismiss; after review the
    /// clip is filed into a chosen plan instead of a fixed day slot.
    var isFreeform = false
    /// The challenge's locked frame. Free-form mode ignores this and uses its
    /// own toggleable orientation instead.
    var orientation: Challenge.Orientation = .portrait
    /// Free-form only: lets the shell block a tab switch that would throw an
    /// unfiled clip away.
    var unfiledGuard: UnfiledClipGuard?
    /// Free-form only: "there's nowhere to file this yet — make somewhere".
    var onStartStory: (() -> Void)?
    let onSave: (URL, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(ClipDraftStore.self) private var drafts
    @Environment(AccountStore.self) private var account
    @State private var recorder = ClipRecorder()
    @State private var ringProgress: CGFloat = 0
    @State private var overlayText = ""
    @State private var showSavePicker = false
    @State private var showNoPlaceExits = false
    @State private var toast: String?
    @State private var freeformOrientation: Challenge.Orientation = .portrait
    @State private var showNotificationPrimer = false
    @State private var dismissAfterPrimer = false
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
    private var bottomInset: CGFloat { isFreeform ? 68 : 8 }
    private var effectiveOrientation: Challenge.Orientation {
        isFreeform ? freeformOrientation : orientation
    }
    private var trimmedOverlayText: String? {
        let text = overlayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    private var localizedMomentTitle: String {
        slotTitle.map { MomentCatalog.localize($0) } ?? Strings.dayN(day)
    }

    var body: some View {
        ZStack {
            OneDay.canvas.ignoresSafeArea()
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
        .onReceive(NotificationCenter.default.publisher(
            for: AVCaptureDevice.wasConnectedNotification
        )) { _ in
            guard recorder.state == .unavailable else { return }
            Task { await recorder.configure() }
        }
        .onDisappear { recorder.teardown() }
        .sheet(
            isPresented: $showNotificationPrimer,
            onDismiss: {
                if dismissAfterPrimer { dismiss() }
                dismissAfterPrimer = false
            }
        ) {
            NotificationPrimerView(challenges: store.challenges)
        }
        .onChange(of: effectiveOrientation) { _, newValue in
            recorder.orientation = newValue
        }
        .onChange(of: recorder.state) { _, state in
            if state == .recording {
                ringProgress = 0
                withAnimation(.linear(duration: clipSeconds)) { ringProgress = 1 }
            }
        }
        .onChange(of: recorder.clipURL) { _, url in
            guard isFreeform, let unfiledGuard else { return }
            unfiledGuard.hasUnfiledClip = url != nil
            unfiledGuard.keep = { keepAsDraft() }
            unfiledGuard.discard = { clearReview() }
        }
    }


    // MARK: - Camera

    private var cameraView: some View {
        VStack(spacing: 10) {
            topBar

            CameraShell(
                name: myName,
                momentTitle: localizedMomentTitle,
                day: day,
                mode: recorder.state == .recording ? .recording : .live,
                timestamp: recorder.recordedAt,
                overlayText: nil,
                clipSeconds: clipSeconds,
                showsPrompt: showsPrompt,
                aspectRatio: effectiveOrientation.aspectRatio
            ) {
                CameraPreview(session: recorder.session) { recorder.attachPreview($0) }
            }
            .layoutPriority(1)

            bottomControls
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, bottomInset)
    }

    private var recordButtonVisual: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.55), lineWidth: 4)
                .frame(width: 66, height: 66)
            Circle()
                .fill(myTint)
                .frame(width: 50, height: 50)
        }
    }

    /// The whole control surface starts recording. The centered layout makes
    /// the primary camera action obvious and gives it a forgiving tap target.
    private var idleRecordingControl: some View {
        Button {
            recorder.startRecording(seconds: clipSeconds)
        } label: {
            VStack(spacing: 5) {
                recordButtonVisual
                Text(Strings.captureState(recording: false, secondsLabel: clipSecondsText))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.captureState(
            recording: false,
            secondsLabel: clipSecondsText
        ))
    }

    /// While recording: a compact countdown row that leaves the camera frame
    /// large enough on short devices such as iPhone SE.
    private var recordingControls: some View {
        HStack(spacing: 12) {
            WaveformBars(tint: myTint)
            countdownRing
            Text(Strings.tapToStop)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
    }

    private var countdownRing: some View {
        Button {
            recorder.stopRecording()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 4)
                    .frame(width: 68, height: 68)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(myTint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 68, height: 68)
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let elapsed = context.date.timeIntervalSince(recorder.recordedAt ?? context.date)
                    let remaining = max(Int((clipSeconds - elapsed).rounded(.up)), 0)
                    Text("\(remaining)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(myTint)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Review (Use / Retake)

    private func reviewView(_ url: URL) -> some View {
        VStack(spacing: 10) {
            topBar

            CameraShell(
                name: myName,
                momentTitle: localizedMomentTitle,
                day: day,
                mode: .review,
                timestamp: recorder.recordedAt,
                overlayText: overlayTextFocused ? nil : trimmedOverlayText,
                clipSeconds: clipSeconds,
                showsPrompt: showsPrompt,
                aspectRatio: effectiveOrientation.aspectRatio
            ) {
                ZStack {
                    LoopingClipPlayer(url: url)
                    // The caption is typed right where it lands in the film —
                    // center of the frame, not in a bar below the video.
                    CaptionOverlayEditor(text: $overlayText, isFocused: $overlayTextFocused)
                }
            }
            .layoutPriority(1)

            HStack(spacing: 10) {
                Button {
                    if isFreeform {
                        // Both dead ends used to end at a toast, which left
                        // retake-or-leave as the only moves — and leaving meant
                        // losing the clip. Now they end at a choice instead.
                        if filingCandidates.isEmpty {
                            showNoPlaceExits = true
                        } else {
                            showSavePicker = true
                        }
                    } else {
                        onSave(url, trimmedOverlayText)
                        offerNotificationPrimer(dismissWhenFinished: true)
                    }
                } label: {
                    Label(isFreeform ? Strings.fileToPlan : Strings.useClip,
                          systemImage: isFreeform ? "tray.and.arrow.down.fill" : "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(myTint, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    recorder.retake()
                    ringProgress = 0
                } label: {
                    Label(Strings.retake, systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, bottomInset)
        .confirmationDialog(Strings.fileThisClipTo, isPresented: $showSavePicker, titleVisibility: .visible) {
            ForEach(filingCandidates) { challenge in
                Button(ChallengePresenter(challenge: challenge).displayTitle) {
                    file(url, to: challenge)
                }
            }
        }
        .confirmationDialog(
            Strings.noPlaceYet,
            isPresented: $showNoPlaceExits,
            titleVisibility: .visible
        ) {
            Button(Strings.saveAsDraft) { keepAsDraft() }
            // Keep the clip first: walking to the composer unmounts this screen,
            // which is precisely how clips used to disappear.
            Button(Strings.createStoryNow) { keepAsDraft(then: onStartStory) }
        } message: {
            Text(noPlaceMessage)
        }
    }

    /// Why there's nowhere to file it — no stories at all, or none in this frame.
    private var noPlaceMessage: String {
        store.challenges.isEmpty
            ? Strings.makePlanFirst
            : Strings.noMatchingPlan(landscape: effectiveOrientation == .landscape)
    }

    // MARK: - Free-form filing

    private var filingCandidates: [Challenge] {
        ClipFiling.candidates(in: store.challenges, orientation: effectiveOrientation)
    }

    /// Free-form: file the clip into a chosen plan's first open slot.
    private func file(_ url: URL, to challenge: Challenge) {
        // Unreachable through the sheet, which only lists stories with room in
        // them — but filing into a full story used to mean overwriting a clip,
        // so this refuses rather than trusting the caller.
        guard let day = ClipFiling.targetDay(in: challenge) else {
            showToast(Strings.storyIsFull)
            return
        }
        store.saveClip(from: url, day: day, challengeID: challenge.id, overlayText: trimmedOverlayText)
        recorder.retake()
        ringProgress = 0
        overlayText = ""
        showToast(Strings.filedTo(ChallengePresenter(challenge: challenge).displayTitle))
        offerNotificationPrimer(dismissWhenFinished: false)
    }

    /// Copy the clip somewhere permanent so it survives leaving this screen.
    ///
    /// On failure this deliberately does **not** retake: the temp file is still
    /// the only copy, so clearing the review would finish the job the bug used
    /// to do. Staying put leaves a retry available.
    private func keepAsDraft(then next: (() -> Void)? = nil) {
        guard let url = recorder.clipURL else { return }
        do {
            try drafts.keep(
                tempURL: url,
                orientation: effectiveOrientation,
                overlayText: trimmedOverlayText)
            clearReview()
            showToast(Strings.draftKept)
            next?()
        } catch {
            showToast(Strings.draftSaveFailed)
        }
    }

    private func clearReview() {
        recorder.retake()
        ringProgress = 0
        overlayText = ""
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.9))
            if toast == text { withAnimation { toast = nil } }
        }
    }

    private func offerNotificationPrimer(dismissWhenFinished: Bool) {
        guard !NotificationPreferences.primerSeen,
              !NotificationPreferences.eveningEnabled
        else {
            if dismissWhenFinished { dismiss() }
            return
        }
        dismissAfterPrimer = dismissWhenFinished
        showNotificationPrimer = true
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
            Button(Strings.retryCamera) {
                Task { await recorder.configure() }
            }
            .buttonStyle(.borderedProminent)
            .tint(myTint)
            #if DEBUG
            CaptionEditor(text: $overlayText, isFocused: $overlayTextFocused)
            Button(Strings.useDemoClip(localizedMomentTitle)) {
                Task {
                    guard let demo = await DemoClipFactory.makeClip(
                        moment: day,
                        label: localizedMomentTitle,
                        author: myName,
                        seconds: clipSeconds,
                        orientation: effectiveOrientation)
                    else { return }
                    // Free-form has no `onSave` — its clips are filed from the
                    // review screen — so hand the demo to the recorder and let
                    // it walk the same path a real take does.
                    if isFreeform {
                        recorder.acceptDemoClip(demo)
                    } else {
                        onSave(demo, trimmedOverlayText)
                        offerNotificationPrimer(dismissWhenFinished: true)
                    }
                }
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
                    Image(systemName: "rectangle.portrait")
                        .font(.system(size: 18, weight: .bold))
                        .rotationEffect(freeformOrientation == .landscape ? .degrees(90) : .zero)
                        .foregroundStyle(.black.opacity(0.78))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.92), in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.switchOrientation)
                .disabled(recorder.state == .recording || recorder.clipURL != nil)
                .opacity(recorder.state == .recording || recorder.clipURL != nil ? 0.45 : 1)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.92), in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            VStack(spacing: 1) {
                OneDayBrandLogo(width: 92)
                Text(localizedMomentTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: 170)

            Spacer(minLength: 8)

            Button { recorder.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.92), in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.flipCamera)
            .disabled(recorder.state != .ready || recorder.clipURL != nil)
            .opacity(recorder.state == .ready && recorder.clipURL == nil ? 1 : 0.45)
        }
    }

    private var bottomControls: some View {
        Group {
            if recorder.state == .recording {
                recordingControls
            } else {
                idleRecordingControl
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 28))
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
