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
    /// How many moments the story has, so the camera's progress bars can be
    /// about this story rather than decoration. 0 = no story behind this take
    /// (free-form), and then no indicator is drawn at all.
    var momentCount = 0
    /// The story's clip length. Kept so callers can still pass it, but no
    /// longer read by the shutter: every take is `takeSeconds` long since
    /// tap-to-film, and the timer chip that cycled this is gone.
    @State var clipLength: Challenge.ClipLength = .tiny
    var showsPrompt = true
    /// Free-form mode (the camera tab): no cover to dismiss; after review the
    /// clip is filed into a chosen plan instead of a fixed day slot.
    var isFreeform = false
    /// The challenge's locked frame. Free-form mode ignores this and uses its
    /// own toggleable orientation instead.
    var orientation: Challenge.Orientation = .portrait
    /// The story's camera (1.5). Set, everyone in the story films with it and
    /// the picker is hidden; nil (free-form, older stories) uses your own pick.
    var lockedCamera: CameraStyle? = nil
    /// Free-form only: lets the shell block a tab switch that would throw an
    /// unfiled clip away.
    var unfiledGuard: UnfiledClipGuard?
    /// Free-form only: "there's nowhere to file this yet — make somewhere".
    var onStartStory: (() -> Void)?
    /// Free-form only: back to the tab the camera came from. The shell hides
    /// its bar while the camera is up (1.5), so this is the ✕. The shell's own
    /// unfiled-clip guard asks before a take in review is lost.
    var onCloseFreeform: (() -> Void)?
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
    /// Raised when the close button is pressed with a take still in review.
    ///
    /// The free-form camera has had this guard since `UnfiledClipGuard` —
    /// leaving with a clip in review asks first. The per-moment camera, opened
    /// as a modal from a story, never got the other half: you filmed two
    /// seconds, tapped X out of habit, and `teardown()` deleted the temp file
    /// on the way out with nothing on screen to say it had happened.
    @State private var askBeforeDiscarding = false
    /// Whether the fine zoom row has replaced the preset chips. The chips
    /// cover 0.5x / 1x / 2x; this covers everything between and above them.
    @State private var showsZoomSlider = false
    /// A pinch reports a running multiple of where it began, so where it began
    /// has to be remembered for the length of the gesture. nil = not pinching.
    @State private var pinchStartZoom: CGFloat?
    /// How far the phone is turned from upright: 0, or ±90 held sideways.
    /// The screen stays portrait (as the system Camera does); the buttons turn
    /// by this much so they read upright, and the frame says it's 横拍.
    /// 横拍, switched on by hand. Only the button turns the camera's layout;
    /// turning the phone by itself doesn't (not in 1.5).
    @State private var manualSideways = false
    /// 「横拍」 is a notice, not a fixture: up for `badgeSeconds` on turning
    /// sideways, then gone so it doesn't sit on the picture.
    @State private var showsSidewaysBadge = false
    private static let badgeSeconds = 1.5
    private var deviceTurn: Double { manualSideways ? 90 : 0 }
    private var isSideways: Bool { deviceTurn != 0 }
    /// Set once this screen has decided to go — the toast saying what happened
    /// is on screen and the dismiss is a beat behind it. Blocks the shutter in
    /// that beat, so a take can't start on a camera that's about to close.
    @State private var isLeaving = false
    @FocusState private var overlayTextFocused: Bool

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// Applied to the take you're deciding about. Not to the live camera and
    /// not to the file — but this is the first time you see yourself back, and
    /// deciding whether to retake off a picture the app will never show you
    /// again is the wrong way round.
    @AppStorage(PersonalEffectParameters.storageKey) private var look: PersonalEffectParameters = .none

    /// Whoever's signed in records the clip — solo challenges have no
    /// account, so this (and the identity tint it drives) falls back to a
    /// fixed default.
    private var myName: String? { account.account?.displayName }
    /// Only for what's *about* you: the frame around the picture and the
    /// countdown ring of the take you're filming. Buttons are actions, and
    /// actions are brand blue everywhere in the app — an identity-tinted "Use"
    /// made the camera the one screen where the primary button changed colour
    /// with whoever was signed in.
    private var myTint: Color { Color.oneDayBrand }
    @AppStorage(CameraStyle.storageKey) private var cameraStyle: CameraStyle = CameraStyle.defaultCamera

    /// Every take is two seconds: one tap, the camera stops itself. Hold-to-
    /// record gave clips of every length, which made the stitched film uneven
    /// and asked people to judge timing while also framing the shot.
    static let takeSeconds: Double = 2
    private var clipSeconds: Double { Self.takeSeconds }
    private var clipSecondsText: String { Challenge.ClipLength.tiny.secondsLabel }
    /// The free-form camera used to leave 68pt here for the floating bar
    /// under it. The bar is hidden while the camera is up as of 1.5.
    private var bottomInset: CGFloat { 8 }
    /// What this take is filmed with: the story's camera when it has one.
    private var activeCamera: CameraStyle { lockedCamera ?? cameraStyle }

    /// Portrait from 1.5 on: the camera decides the shape now. A story saved
    /// with landscape or square keeps it.
    private var effectiveOrientation: Challenge.Orientation {
        isFreeform ? freeformOrientation : orientation
    }
    private var trimmedOverlayText: String? {
        let text = overlayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    /// Falls back to 「这个瞬间」, not 「第 N 天」: a time-only story passes no
    /// slot title, and its moments are not days — the top bar of a camera
    /// opened at 3pm said 「第 1 天」. The stamp on the frame never shows this
    /// for those stories (`showsPrompt` is off for them), only the header.
    private var localizedMomentTitle: String {
        slotTitle.map { MomentCatalog.localize($0) } ?? Strings.thisMoment
    }

    /// What to stamp on the picture as the moment's name — nil in free-form,
    /// where the take doesn't belong to a moment yet and "Free-form" is a mode
    /// label rather than something the film will ever say. The header above the
    /// frame still names the mode; the frame itself only shows what survives
    /// into the export.
    private var stampedMomentTitle: String? {
        isFreeform ? nil : localizedMomentTitle
    }

    // Split in three so each chain type-checks on its own: as one expression
    // it ran past the compiler's time limit on CI's slower runners.
    var body: some View {
        observingTake(withCaptureLifecycle(screen))
    }

    private var screen: some View {
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
    }

    private func withCaptureLifecycle(_ content: some View) -> some View {
        content
        .task {
            recorder.orientation = effectiveOrientation
            if !CameraStyle.selectable.contains(cameraStyle) {
                cameraStyle = CameraStyle.defaultCamera
            }
            recorder.cameraStyle = activeCamera
            await recorder.configure()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: AVCaptureDevice.wasConnectedNotification
        )) { _ in
            guard recorder.state == .unavailable else { return }
            Task { await recorder.configure() }
        }
        .onDisappear { recorder.teardown() }
        .allowsHitTesting(!isLeaving)
        // Felt rather than seen: the thumb is still on or near the shutter,
        // covering the ring, at exactly the moments these fire.
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.state) { _, now in
            now == .recording
        }
        .sensoryFeedback(.success, trigger: recorder.clipURL) { _, now in now != nil }
        .sensoryFeedback(.error, trigger: recorder.failureCount)
        .onChange(of: recorder.failureCount) { _, _ in
            ringProgress = 0
            showToast(Strings.recordingFailed)
        }
        .confirmationDialog(
            // Not the free-form 「这段还没归档」: this take already has a home,
            // the moment the camera was opened from, so the first answer
            // offered is to put it there.
            isFreeform ? Strings.keepClipQuestion : Strings.unusedClipQuestion,
            isPresented: $askBeforeDiscarding,
            titleVisibility: .visible
        ) {
            // X out of habit used to offer keep-as-draft or discard — never the
            // thing the take was filmed for. Same call as the Use button.
            if !isFreeform, let url = recorder.clipURL {
                Button(Strings.useClip) {
                    onSave(url, trimmedOverlayText)
                    dismiss()
                }
            }
            Button(Strings.keepClip) { keepAsDraft { dismiss() } }
            Button(Strings.discardClip, role: .destructive) {
                clearReview()
                dismiss()
            }
            Button(Strings.cancel, role: .cancel) {}
        } message: {
            Text(Strings.keepClipFootnote)
        }
    }

    private func observingTake(_ content: some View) -> some View {
        content
        .onChange(of: effectiveOrientation) { _, newValue in
            recorder.orientation = newValue
        }
        .onChange(of: cameraStyle) { _, _ in
            recorder.cameraStyle = activeCamera
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
                momentTitle: stampedMomentTitle,
                day: day,
                momentCount: momentCount,
                mode: recorder.state == .recording ? .recording : .live,
                timestamp: recorder.recordedAt,
                overlayText: nil,
                clipSeconds: clipSeconds,
                showsPrompt: showsPrompt,
                aspectRatio: activeCamera.aspectRatio(for: effectiveOrientation)
                    ?? effectiveOrientation.aspectRatio,
                cameraStyle: activeCamera,
                turn: deviceTurn
            ) {
                #if DEBUG && targetEnvironment(simulator)
                if ClipRecorder.isSimulated {
                    SimulatedCameraPreview()
                } else {
                    livePreview
                }
                #else
                livePreview
                #endif
            }
            // Top-left, inside the frame: a refused microphone
            // films silent clips, and a silent preview looks exactly like a
            // working one. iOS won't ask twice, so the only fix is Settings.
            .overlay(alignment: .topLeading) {
                if !recorder.hasAudioAccess {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString)
                        else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        Label(Strings.noSoundOpenSettings, systemImage: "mic.slash.fill")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .cameraGlass(.capsule)
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
            // Pinch the picture itself, which is where the hand already is.
            // The chips are the quick answer; this is the whole range, and it
            // stays live while recording — zooming mid-take is the point of
            // having it on the preview rather than in a setting.
            .gesture(
                MagnifyGesture(minimumScaleDelta: 0.01)
                    .onChanged { value in
                        let start = pinchStartZoom ?? recorder.zoom
                        pinchStartZoom = start
                        recorder.setZoom(start * value.magnification)
                    }
                    .onEnded { _ in pinchStartZoom = nil }
            )
            // Over the picture, above the burn-in. The moment's name and the
            // progress bars sit in the bottom ~56pt of the frame and are
            // promises about the export, so the offset is what keeps this
            // legal — see `ZoomControlRow`.
            .overlay(alignment: zoomAlignment) {
                if isSideways {
                    // Along the edge that is the bottom of the landscape take,
                    // turned with the phone, clear of the burn-in there.
                    zoomControls
                        .fixedSize()
                        .rotationEffect(.degrees(deviceTurn))
                        .frame(width: 56)
                        .padding(deviceTurn > 0 ? .leading : .trailing, Self.burnInHeight - 16)
                } else {
                    zoomControls
                        .padding(.bottom, Self.burnInHeight)
                }
            }
            .overlay { if showsSidewaysBadge { sidewaysBadge.transition(.opacity) } }
            .layoutPriority(1)

            shutterRow
        }
        .animation(OneDay.Motion.snap, value: deviceTurn)
        .onChange(of: isSideways) { _, sideways in flashSidewaysBadge(sideways) }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, bottomInset)
    }

    /// 「横拍」 over the middle of the frame, turned to read upright in the
    /// hand, so a sideways take never looks like a portrait one.
    private var sidewaysBadge: some View {
        Label(Strings.filmingSideways, systemImage: "rectangle.landscape.rotate")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.45), in: Capsule())
            .rotationEffect(.degrees(deviceTurn))
            .allowsHitTesting(false)
            .accessibilityIdentifier("camera-sideways")
    }

    private var zoomAlignment: Alignment {
        guard isSideways else { return .bottom }
        return deviceTurn > 0 ? .leading : .trailing
    }

    private func flashSidewaysBadge(_ sideways: Bool) {
        guard sideways else {
            withAnimation(OneDay.Motion.soft) { showsSidewaysBadge = false }
            return
        }
        withAnimation(OneDay.Motion.soft) { showsSidewaysBadge = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.badgeSeconds))
            withAnimation(OneDay.Motion.soft) { showsSidewaysBadge = false }
        }
    }

    /// How much of the frame's bottom edge the burn-in block occupies:
    /// `progressBars` over `momentPill`, plus the overlay's own edge inset.
    /// The zoom control clears it rather than covering it.
    private static let burnInHeight: CGFloat = 72

    private var recordButtonVisual: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.55), lineWidth: 4)
                .frame(width: 66, height: 66)
            Circle()
                .fill(Color.oneDayBrand)
                .frame(width: 50, height: 50)
        }
    }

    /// One tap films a two-second take that stops on its own. A `Button`
    /// again: with nothing to hold, firing on release is what a tap means.
    private var idleRecordingControl: some View {
        CenteredCaptureControl(instruction: Strings.tapToFilmTwoSeconds) {
            Button { startCapture() } label: {
                recordButtonVisual
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Strings.captureState(
            recording: false,
            secondsLabel: clipSecondsText
        ))
        .accessibilityHint(Strings.tapToFilmTwoSeconds)
        .accessibilityAction { startCapture() }
    }

    /// Match the idle shutter's center axis; translated instructions sit below
    /// rather than pushing the countdown sideways.
    private var recordingControls: some View {
        CenteredCaptureControl(instruction: Strings.filmingTwoSeconds) {
            countdownRing
        }
    }

    private func startCapture() {
        guard !isLeaving, recorder.state == .ready, recorder.clipURL == nil else { return }
        recorder.startRecording(seconds: clipSeconds)
    }

    /// A countdown, not a control: the take stops itself at two seconds and a
    /// tap here does nothing. Cutting a two-second take shorter only ever made
    /// a clip too short to see.
    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)
                .frame(width: 68, height: 68)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(myTint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 68, height: 68)
            countdownNumber
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.captureState(recording: true, secondsLabel: clipSecondsText))
    }

    private var countdownNumber: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = context.date.timeIntervalSince(recorder.recordedAt ?? context.date)
            let remaining = max(Int((clipSeconds - elapsed).rounded(.up)), 0)
            Text("\(remaining)")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(myTint)
                .monospacedDigit()
        }
    }

    // MARK: - Review (Use / Retake)

    private func reviewView(_ url: URL) -> some View {
        VStack(spacing: 10) {
            topBar

            CameraShell(
                name: myName,
                momentTitle: stampedMomentTitle,
                day: day,
                momentCount: momentCount,
                mode: .review,
                timestamp: recorder.recordedAt,
                overlayText: overlayTextFocused ? nil : trimmedOverlayText,
                clipSeconds: clipSeconds,
                showsPrompt: showsPrompt,
                aspectRatio: recorder.cameraStyle.aspectRatio(for: effectiveOrientation)
                    ?? effectiveOrientation.aspectRatio,
                showsDate: recorder.cameraStyle == .standard
            ) {
                ZStack {
                    // Immediate review is always the camera truth; grading belongs elsewhere.
                    LoopingClipPlayer(url: url, look: .none)
                    // The caption is typed right where it lands in the film —
                    // center of the frame, not in a bar below the video.
                    CaptionOverlayEditor(text: $overlayText, isFocused: $overlayTextFocused)
                }
            }
            .layoutPriority(1)

            HStack(spacing: 10) {
                Button {
                    if isFreeform {
                        // 1.5: a free take goes straight into 我的. Filing it
                        // into a story is still there, from 我的's drafts.
                        keepAsDraft()
                    } else {
                        onSave(url, trimmedOverlayText)
                        dismiss()
                    }
                } label: {
                    Label(isFreeform ? Strings.saveToMine : Strings.useClip,
                          systemImage: isFreeform ? "tray.and.arrow.down.fill" : "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(OneDay.onBrand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        // The brand gradient `.primaryAction` uses, at this
                        // row's height: the full style is 17pt type and 17pt
                        // padding, which would stand taller than 重拍 beside it.
                        .background(OneDay.brandHorizontal, in: Capsule())
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
        // Same rule as `ClipPreviewView`: the keyboard covers the buttons
        // rather than squeezing the frame. Typing a caption used to shrink the
        // picture the caption was being placed on.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showSavePicker) {
            ClipFilingSheet(candidates: filingCandidates) { chosen in
                file(url, to: chosen)
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
            : Strings.noMatchingPlan(effectiveOrientation)
    }

    // MARK: - Free-form filing

    private var filingCandidates: [Challenge] {
        ClipFiling.candidates(in: store.challenges, orientation: effectiveOrientation)
    }

    /// Free-form: file the clip into each chosen plan's first open slot.
    ///
    /// Takes a list as of 1.3 — one take of an afternoon belongs in your own
    /// story *and* in the room you shared it with, and the single-choice dialog
    /// this replaced made that two takes. `ClipFileStore.storeClip` copies, so
    /// the one temp URL can be filed once per story; the review is only cleared
    /// after the loop, because clearing it calls `recorder.retake()` and that
    /// is what invalidates `url`.
    private func file(_ url: URL, to challenges: [Challenge]) {
        var landed = 0
        var lastTitle = ""

        for challenge in challenges {
            // Unreachable through the sheet, which only lists stories with room
            // in them — but filing into a full story used to mean overwriting a
            // clip, so this refuses rather than trusting the caller.
            guard let day = ClipFiling.targetDay(in: challenge) else { continue }
            store.saveClip(
                from: url, day: day, challengeID: challenge.id,
                overlayText: trimmedOverlayText)
            landed += 1
            lastTitle = ChallengePresenter(challenge: challenge).displayTitle
        }

        guard landed > 0 else {
            showToast(Strings.storyIsFull)
            return
        }

        recorder.retake()
        ringProgress = 0
        overlayText = ""
        showToast(landed == 1 ? Strings.filedTo(lastTitle) : Strings.filedToCount(landed))
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
            // The next step — dismissing, or walking to the composer — unmounts
            // this screen and the toast with it, so it used to say 已存起来 to
            // nobody. A beat first, with the camera held still meanwhile.
            if let next {
                isLeaving = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    next()
                    isLeaving = false
                }
            }
        } catch {
            showToast(Strings.draftSaveFailed)
        }
    }

    /// Whether the camera is off because this person turned it off.
    ///
    /// Read at draw time rather than stored: coming back from Settings having
    /// granted it doesn't re-run `configure()` on its own, and a stale `false`
    /// here would put the dead "try again" button back.
    private var cameraAccessDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .denied
    }

    /// The close button. Asks first when there is a take that would go with it.
    ///
    /// Nothing to lose means no dialog: a confirmation people see every time
    /// they back out of a camera they opened by mistake is one they learn to
    /// dismiss without reading, which is how the one that mattered gets missed.
    private func closeRequested() {
        guard recorder.clipURL != nil else {
            dismiss()
            return
        }
        // A free take goes to 我的 without a question; a moment's take still
        // asks, since its first answer is to use it for that moment.
        if isFreeform {
            keepAsDraft { dismiss() }
            return
        }
        askBeforeDiscarding = true
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


    private var unavailableView: some View {
        VStack(spacing: 18) {
            topBar
            Spacer()
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            // Denied is a different situation from unavailable, and the
            // difference is the only thing that matters here: iOS will not ask
            // again once someone has said no, so `requestAccess` returns false
            // forever and "try again" is a button that cannot work. Someone who
            // mistapped "Don't Allow" on first run was stuck in that loop with
            // nothing in the app ever mentioning Settings — in an app whose
            // entire purpose is the camera.
            if cameraAccessDenied {
                Text(Strings.cameraDeniedTitle)
                    .font(.headline)
                Text(Strings.cameraDeniedFootnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(Strings.openSettings) {
                    guard let url = URL(string: UIApplication.openSettingsURLString)
                    else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.oneDayBrand)
            } else {
                Text(Strings.cameraUnavailable)
                    .font(.headline)
                Button(Strings.retryCamera) {
                    Task { await recorder.configure() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.oneDayBrand)
            }
            // Same gate as the home screen's demo button, for the same
            // reason: the Simulator has no camera, so this is the only way to
            // get footage into a story on a Mac — and it does not belong on the
            // screen the rest of the time. See `DemoEntries`.
            #if DEBUG
            if DemoEntries.areEnabled {
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
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.oneDayBrand)
            }
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

    /// The wordmark, the moment's name, and — outside the free-form tab — the
    /// way out. Nothing you press mid-shoot.
    ///
    /// 画幅 and 翻转 used to flank the wordmark up here, which put the two
    /// controls you reach for while filming at the far end of the phone from
    /// your thumb. They are beside the shutter now; see `shutterRow`. What is
    /// left is the two things you read rather than press, so the row shrank
    /// from 44pt to the height of its own text.
    private var topBar: some View {
        HStack {
            if isFreeform {
                if let onCloseFreeform {
                    Button { onCloseFreeform() } label: {
                        Image(systemName: "xmark")
                            .cameraGlass()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.closeCamera)
                    .accessibilityIdentifier("camera-close")
                } else {
                    Color.clear.frame(width: 44, height: 1)
                }
            } else {
                Button { closeRequested() } label: {
                    Image(systemName: "xmark")
                        .cameraGlass()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.closeCamera)
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

            Color.clear.frame(width: 44, height: 1)
        }
    }

    // MARK: - Zoom

    /// Drawn in both `.live` and `.recording`: zooming mid-take is allowed by
    /// the capture pipeline and is half of why anybody wants 2x.
    @ViewBuilder
    private var zoomControls: some View {
        let presets = recorder.zoomPresets
        // One preset means one lens with nothing to reach for — the front
        // camera on an older phone, or the Simulator's borrowed webcam. A
        // single dead chip would be worse than no row at all.
        if presets.count > 1 {
            ZoomControlRow(
                presets: presets,
                capabilities: recorder.zoomCapabilities,
                tint: Color.oneDayBrand,
                zoom: zoomBinding,
                showsSlider: $showsZoomSlider)
        }
    }

    private var zoomBinding: Binding<CGFloat> {
        Binding(
            get: { recorder.zoom },
            set: { recorder.setZoom($0) })
    }

    /// Just the shutter, with the frame and flip controls either side of it.
    ///
    /// Three shapes in two rounds. It was a white rounded card holding four
    /// wide zoom capsules, a 66pt shutter and the words 轻点拍摄 — about 150pt
    /// of furniture under a 9:16 picture laid out `.fit`, so every point came
    /// straight off the viewfinder. Then the card and the caption went and the
    /// zoom became a ticked track, still under the picture. Now the zoom is
    /// over the picture (above the burn-in) and this row is one control tall.
    ///
    /// The two 34pt circles are 画幅 and 翻转, moved down from the top bar.
    /// They were up there flanking the wordmark, which put the two things you
    /// reach for mid-shoot at the far end of the phone from your thumb; beside
    /// the shutter they are where the hand already is. The top bar keeps the
    /// wordmark and the moment's name — the two things you read rather than
    /// press.
    ///
    /// `recordingControls` keeps a caption: mid-take it says the camera will
    /// stop itself, since the ring it sits under is counting, not a button.
    private var shutterRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                sidewaysButton
                if recorder.supportsDualCamera { dualCameraButton.rotationEffect(.degrees(deviceTurn)) }
            }
            .frame(maxWidth: .infinity)

            ZStack {
                if recorder.state == .recording {
                    recordingControls
                } else {
                    idleRecordingControl
                }
            }

            HStack(spacing: 6) {
                flipButton.rotationEffect(.degrees(deviceTurn))
                if lockedCamera == nil { cameraStyleButton.rotationEffect(.degrees(deviceTurn)) }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// 横拍: lit when on. Turns the camera's buttons and badge for holding
    /// the phone sideways; the take itself follows how the phone is held.
    private var sidewaysButton: some View {
        Button {
            withAnimation(OneDay.Motion.snap) { manualSideways.toggle() }
        } label: {
            Image(systemName: "rectangle.landscape.rotate")
                .foregroundStyle(isSideways ? Color.oneDayBrand : .white)
                .cameraGlass()
                .rotationEffect(.degrees(deviceTurn))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.filmingSideways)
        .accessibilityAddTraits(isSideways ? .isSelected : [])
        .accessibilityIdentifier("camera-sideways-toggle")
        .disabled(recorder.state == .recording)
    }

    private var orientationButton: some View {
        Button {
            // Cycles rather than toggles now that there are three frames. The
            // glyph is the current one, so which way round the cycle runs
            // doesn't have to be learned.
            freeformOrientation = switch freeformOrientation {
            case .portrait: .landscape
            case .landscape: .square
            case .square: .portrait
            }
        } label: {
            Image(systemName: SetupStep.orientationIcon(freeformOrientation))
                .cameraGlass()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.switchOrientation)
        .disabled(recorder.state == .recording || recorder.clipURL != nil)
        .opacity(recorder.state == .recording || recorder.clipURL != nil ? 0.45 : 1)
    }

    /// The main camera full frame and, in dual mode, the other one in the
    /// white-bordered inset — laid out where `PiPComposer` will put it in the
    /// file. The inset moves and resizes only between takes: the file is
    /// composed from `recorder.insetRect` after the take, so a drag mid-take
    /// would put the inset somewhere the viewfinder never showed it.
    private var livePreview: some View {
        DualCameraStage(
            showsInset: recorder.isDualCamera,
            swapped: recorder.isSwapped,
            inset: recorder.insetRect,
            isEditable: recorder.state == .ready,
            onInsetChange: { recorder.insetRect = $0 },
            onTapInset: { recorder.flipCamera() }
        ) {
            CameraPreview(session: recorder.session) { recorder.attachPreview($0) }
        } secondary: {
            SecondaryCameraPreview(session: recorder.session) {
                recorder.attachSecondaryPreview($0)
            }
        }
    }

    private var dualCameraButton: some View {
        Button { recorder.setDualCamera(!recorder.isDualCamera) } label: {
            DualCameraGlyph(isOn: recorder.isDualCamera)
                .cameraGlass()
                .overlay(dualCameraOnRing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.dualCamera)
        .accessibilityAddTraits(recorder.isDualCamera ? .isSelected : [])
        .disabled(recorder.state != .ready || recorder.clipURL != nil)
        .opacity(recorder.state == .ready && recorder.clipURL == nil ? 1 : 0.45)
    }

    /// A brand ring around the glass when dual mode is on, so on and off
    /// differ by more than the small rectangle's fill.
    private var dualCameraOnRing: some View {
        Circle()
            .strokeBorder(Color.oneDayBrand, lineWidth: 2)
            .frame(width: 38, height: 38)
            .opacity(recorder.isDualCamera ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// Dazz-style: which camera you're holding. Picks the frame, the date and
    /// the tone baked into the next take — see `CameraStyle`.
    private var cameraStyleButton: some View {
        Menu {
            Picker(Strings.cameraPicker, selection: $cameraStyle) {
                ForEach(CameraStyle.selectable) { style in
                    Label(style.displayName, systemImage: style.symbolName).tag(style)
                }
            }
        } label: {
            Image(systemName: cameraStyle.symbolName)
                .cameraGlass()
        }
        .accessibilityLabel(Strings.cameraPicker)
        .accessibilityValue(cameraStyle.displayName)
        .accessibilityIdentifier("camera-style")
        .disabled(recorder.state == .recording || recorder.clipURL != nil)
        .opacity(recorder.state == .recording || recorder.clipURL != nil ? 0.45 : 1)
    }

    private var flipButton: some View {
        Button { recorder.flipCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                .cameraGlass()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.flipCamera)
        .disabled(recorder.state != .ready || recorder.clipURL != nil)
        .opacity(recorder.state == .ready && recorder.clipURL == nil ? 1 : 0.45)
    }
}
