import SwiftUI
import Observation
import AVFoundation
import AVKit

struct RecordClipView: View {
    let day: Int
    var slotTitle: String?
    var momentCount = 0
    @State var clipLength: Challenge.ClipLength = .tiny
    var showsPrompt = true
    var isFreeform = false
    var orientation: Challenge.Orientation = .portrait
    var lockedCamera: CameraStyle? = nil
    var unfiledGuard: UnfiledClipGuard?
    var onCloseFreeform: (() -> Void)?
    var startsSideways = false
    let onSave: (URL, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(ClipDraftStore.self) private var drafts
    @Environment(AccountStore.self) private var account
    @State private var recorder = ClipRecorder()
    @State private var ringProgress: CGFloat = 0
    @State private var overlayText = ""
    @State private var showSavePicker = false
    @State private var sendTo: Set<UUID> = []
    @State private var afterSignIn: (() -> Void)?
    @State private var showNoPlaceExits = false
    @State private var toast: String?
    @State private var freeformOrientation: Challenge.Orientation = .portrait
    @State private var showsZoomSlider = false
    @State private var pinchStartZoom: CGFloat?
    @State private var manualSideways = false
    @State private var tilt = DeviceTiltWatcher(holdSeconds: 0)
    private var deviceTurn: Double { manualSideways ? 90 : 0 }
    private var captureOrientation: Challenge.Orientation {
        manualSideways ? .landscape : effectiveOrientation
    }
    @State private var reviewOrientation: Challenge.Orientation = .portrait
    @State private var measuredReviewAspect: CGFloat?
    private var isSideways: Bool { deviceTurn != 0 }
    @State private var isLeaving = false
    @State private var stopRequested = false
    @FocusState private var overlayTextFocused: Bool

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system


    private var myName: String? { account.account?.displayName }
    private var myTint: Color { Color.oneDayBrand }
    @AppStorage(CameraStyle.storageKey) private var cameraStyle: CameraStyle = CameraStyle.defaultCamera

    static let takeSeconds: Double = 2
    private var clipSeconds: Double { Self.takeSeconds }
    private var clipSecondsText: String { Challenge.ClipLength.tiny.secondsLabel }
    private var bottomInset: CGFloat { isFreeform ? OneDay.tabBarClearance + 8 : 8 }
    private var activeCamera: CameraStyle {
        let camera = lockedCamera ?? cameraStyle
        return CameraStyle.selectable.contains(camera) ? camera : CameraStyle.defaultCamera
    }

    private var effectiveOrientation: Challenge.Orientation {
        isFreeform ? freeformOrientation : orientation
    }
    private var filingOrientation: Challenge.Orientation {
        recorder.clipURL == nil ? captureOrientation : reviewOrientation
    }
    private var trimmedOverlayText: String? {
        let text = overlayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    private var localizedMomentTitle: String {
        slotTitle.map { MomentCatalog.localize($0) } ?? Strings.thisMoment
    }

    private var stampedMomentTitle: String? {
        isFreeform ? nil : localizedMomentTitle
    }

    var body: some View {
        if #available(iOS 18.0, *) {
            observingTake(withCaptureLifecycle(screen))
                .onCameraCaptureEvent(isEnabled: captureControlEnabled) { event in
                    guard event.phase == .ended else { return }
                    capturePressed()
                }
        } else {
            observingTake(withCaptureLifecycle(screen))
        }
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
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .task {
            if startsSideways {
                manualSideways = true
                recorder.forcedLandscape = true
            }
            recorder.orientation = captureOrientation
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
        .onDisappear {
            recorder.teardown()
            unfiledGuard?.isRecording = false
        }
        .allowsHitTesting(!isLeaving)
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.state) { _, now in
            now == .recording
        }
        .sensoryFeedback(.success, trigger: recorder.clipURL) { _, now in now != nil }
        .sensoryFeedback(.error, trigger: recorder.failureCount)
        .onChange(of: recorder.failureCount) { _, _ in
            ringProgress = 0
            showToast(Strings.recordingFailed)
        }
    }

    private func observingTake(_ content: some View) -> some View {
        content
        .signInGate($afterSignIn)
        .onChange(of: effectiveOrientation) { _, newValue in
            recorder.orientation = manualSideways ? .landscape : newValue
        }
        .onChange(of: cameraStyle) { _, _ in
            recorder.cameraStyle = activeCamera
        }
        .onChange(of: filingOrientation) { _, _ in
            sendTo.formIntersection(Set(sendableRooms.map(\.id)))
        }
        .onChange(of: recorder.state) { _, state in
            if state == .ready { stopRequested = false }
            unfiledGuard?.isRecording = state == .recording
            if state == .recording {
                reviewOrientation = captureOrientation
                measuredReviewAspect = nil
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
            .gesture(
                MagnifyGesture(minimumScaleDelta: 0.01)
                    .onChanged { value in
                        let start = pinchStartZoom ?? recorder.zoom
                        pinchStartZoom = start
                        recorder.setZoom(start * value.magnification)
                    }
                    .onEnded { _ in pinchStartZoom = nil }
            )
            .overlay(alignment: zoomAlignment) {
                if isSideways {
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
            .overlay {
                if isSideways && recorder.state != .recording && !tilt.isHeldSideways {
                    sidewaysHint.transition(.opacity)
                }
            }
            .layoutPriority(1)

            shutterRow
        }
        .animation(OneDay.Motion.snap, value: deviceTurn)
        .onChange(of: manualSideways) { _, on in
            recorder.forcedLandscape = on
            recorder.orientation = captureOrientation
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, bottomInset)
    }

    private var sidewaysHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "rotate.left")
                .font(.system(size: 44, weight: .semibold))
            Text(Strings.turnPhoneSideways)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("camera-sideways")
    }

    private var zoomAlignment: Alignment {
        guard isSideways else { return .bottom }
        return deviceTurn > 0 ? .leading : .trailing
    }

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

    private var idleRecordingControl: some View {
        CenteredCaptureControl(instruction: nil) {
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
        .accessibilityIdentifier("camera-shutter")
        .accessibilityAction { startCapture() }
    }

    private var recordingControls: some View {
        CenteredCaptureControl(instruction: nil) {
            Button(action: capturePressed) { countdownRing }
                .buttonStyle(.plain)
                .disabled(stopRequested)
                .accessibilityLabel(Strings.stopRecording)
                .accessibilityIdentifier("camera-stop")
        }
    }

    private var captureControlEnabled: Bool {
        !isLeaving && !stopRequested && recorder.clipURL == nil
            && !showSavePicker && !showNoPlaceExits
            && (recorder.state == .ready || recorder.state == .recording)
    }

    private func capturePressed() {
        guard captureControlEnabled else { return }
        if recorder.state == .recording {
            stopRequested = true
            recorder.stopRecording()
        } else {
            startCapture()
        }
    }

    private func startCapture() {
        guard !isLeaving, recorder.state == .ready, recorder.clipURL == nil else { return }
        stopRequested = false
        recorder.startRecording(seconds: clipSeconds)
    }

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


    private func reviewView(_ url: URL) -> some View {
        VStack(spacing: 10) {
            topBar
            Spacer(minLength: 0)

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
                aspectRatio: measuredReviewAspect
                    ?? recorder.cameraStyle.aspectRatio(for: reviewOrientation)
                    ?? reviewOrientation.aspectRatio,
                showsDate: recorder.cameraStyle == .standard
            ) {
                ZStack {
                    LoopingClipPlayer(url: url)
                    CaptionOverlayEditor(text: $overlayText, isFocused: $overlayTextFocused)
                }
            }
            .layoutPriority(1)
            .task(id: url) {
                let aspect = await ClipGeometry.aspect(of: url)
                guard !Task.isCancelled else { return }
                measuredReviewAspect = aspect
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture-review-frame")
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    if value.translation.width < -80, abs(value.translation.height) < 80 {
                        discardTake()
                    }
                })

            Spacer(minLength: 0)
            if isFreeform { RoomSendList(rooms: sendableRooms, picked: $sendTo) }

            HStack(spacing: OneDay.Space.m) {
                Button {
                    recorder.retake()
                    ringProgress = 0
                } label: {
                    Label(Strings.retake, systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.tool)
                .accessibilityIdentifier("camera-retake")

                Button {
                    if isFreeform {
                        finishFreeTake()
                    } else {
                        onSave(url, trimmedOverlayText)
                        dismiss()
                    }
                } label: {
                    Label(Strings.done, systemImage: "checkmark")
                        .lineLimit(1)
                }
                .buttonStyle(.primaryAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, bottomInset)
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
        } message: {
            Text(noPlaceMessage)
        }
    }

    private var noPlaceMessage: String {
        store.challenges.isEmpty
            ? Strings.makePlanFirst
            : Strings.noMatchingPlan(filingOrientation)
    }


    private var sendableRooms: [Challenge] {
        ClipFiling.rooms(in: store.challenges)
            .sorted { $0.startDate > $1.startDate }
    }

    private var filingCandidates: [Challenge] {
        ClipFiling.candidates(in: store.challenges)
    }

    private func file(_ url: URL, to challenges: [Challenge]) {
        var landed = 0
        var lastTitle = ""

        for challenge in challenges {
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

    @discardableResult
    private func keepAsDraft(then next: (() -> Void)? = nil) -> Bool {
        guard let url = recorder.clipURL else { return false }
        do {
            try drafts.keep(
                tempURL: url,
                orientation: filingOrientation,
                overlayText: trimmedOverlayText,
                recordedAt: recorder.recordedAt ?? .now)
            clearReview()
            showToast(Strings.draftKept)
            if let next {
                isLeaving = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    next()
                    isLeaving = false
                }
            }
            return true
        } catch {
            showToast(Strings.draftSaveFailed)
            return false
        }
    }

    private var cameraAccessDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .denied
    }

    private func closeRequested() {
        guard recorder.clipURL != nil else {
            dismiss()
            return
        }
        if isFreeform {
            finishFreeTake { dismiss() }
            return
        }
        if let url = recorder.clipURL {
            onSave(url, trimmedOverlayText)
        }
        dismiss()
    }

    private func finishFreeTake(then next: (() -> Void)? = nil) {
        guard let url = recorder.clipURL else { next?(); return }
        let eligible = Set(sendableRooms.map(\.id))
        let rooms = sendTo.intersection(eligible)
        guard !rooms.isEmpty else {
            keepAsDraft(then: next)
            return
        }
        guard account.isSignedIn else {
            afterSignIn = { finishFreeTake(then: next) }
            return
        }
        let at = recorder.recordedAt ?? .now
        for id in rooms {
            store.sendToRoom(from: url, roomID: id, overlayText: trimmedOverlayText, recordedAt: at)
        }
        sendTo = []
        clearReview()
        showToast(Strings.sentToRooms)
        if let next {
            isLeaving = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                next()
                isLeaving = false
            }
        }
    }

    private func discardTake() {
        sendTo = []
        clearReview()
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

            if cameraAccessDenied {
                Text(Strings.cameraDeniedTitle)
                    .font(.headline)
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
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var topBar: some View {
        let turn = recorder.clipURL == nil ? deviceTurn : 0
        let sideways = turn != 0
        return HStack {
            if isFreeform {
                if let onCloseFreeform {
                    Button { onCloseFreeform() } label: {
                        Image(systemName: "xmark")
                            .cameraGlass()
                            .rotationEffect(.degrees(turn))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.closeCamera)
                    .accessibilityIdentifier("camera-close")
                    .disabled(recorder.state == .recording)
                } else {
                    Color.clear.frame(width: 44, height: 1)
                }
            } else {
                Button { closeRequested() } label: {
                    Image(systemName: "xmark")
                        .cameraGlass()
                        .rotationEffect(.degrees(turn))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.closeCamera)
                .disabled(recorder.state == .recording)
            }

            Spacer(minLength: 8)

            VStack(spacing: 1) {
                OneDayBrandLogo(width: sideways ? 64 : 92)
                Text(localizedMomentTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: sideways ? 80 : 170)
            .rotationEffect(.degrees(turn))
            .offset(y: sideways ? -14 : 0)

            Spacer(minLength: 8)

            Color.clear.frame(width: 44, height: 1)
        }
    }


    @ViewBuilder
    private var zoomControls: some View {
        let presets = recorder.zoomPresets
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
                flashButton.rotationEffect(.degrees(deviceTurn))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

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

    private var dualCameraOnRing: some View {
        Circle()
            .strokeBorder(Color.oneDayBrand, lineWidth: 2)
            .frame(width: 38, height: 38)
            .opacity(recorder.isDualCamera ? 1 : 0)
            .allowsHitTesting(false)
    }

    private var flashButton: some View {
        Button { recorder.toggleTorch() } label: {
            Image(systemName: recorder.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                .foregroundStyle(recorder.isTorchOn && recorder.canUseTorch ? Color.oneDayButter : .white)
                .cameraGlass()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.cameraFlash)
        .accessibilityAddTraits(recorder.isTorchOn ? .isSelected : [])
        .accessibilityIdentifier("camera-flash")
        .disabled(!recorder.canUseTorch)
        .opacity(recorder.canUseTorch ? 1 : 0.45)
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

private struct RoomSendList: View {
    let rooms: [Challenge]
    @Binding var picked: Set<UUID>

    var body: some View {
        if !rooms.isEmpty {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(rooms) { room in row(room) }
                }
            }
            .frame(maxHeight: min(CGFloat(rooms.count) * 50, 150))
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(_ room: Challenge) -> some View {
        let on = picked.contains(room.id)
        return Button {
            if on { picked.remove(room.id) } else { picked.insert(room.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(on ? Color.oneDayBrand : OneDay.inkFaint)
                Text(ChallengePresenter(challenge: room).displayTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(OneDay.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("send-room-row")
    }
}
