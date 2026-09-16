import SwiftUI

/// Looking back at one clip.
///
/// The video is the screen. Everything else floats on top of it.
///
/// It used to be a `ScrollView`: a 340pt-wide card in a `NavigationStack`,
/// which for a 9:16 clip is 604pt tall — so on a 667pt screen the video's
/// bottom edge landed at 708pt and the comment bar's top edge at 704pt, and the
/// reactions, the timestamp, the comment thread and the re-record button were
/// all below the fold of a screen showing a two-second clip. Nobody scrolls to
/// find out what happens under a video that's already playing.
///
/// Social UI lives in `ClipPreviewComponents.swift`; this file owns state and
/// store calls.
struct ClipPreviewView: View {
    let day: Int
    var slotTitle: String?
    /// How many moments the story has, for the "4 / 5" chip. 0 hides the count
    /// — a clip opened without its story behind it has no denominator.
    var momentCount = 0
    var authorName: String?
    var overlayText: String?
    /// The caption's sticker as it was handed in, for a clip this screen can't
    /// read a live card for — a friend's take, or a page of the deck.
    var captionSticker: CaptionSticker?
    var clipLength: Challenge.ClipLength = .tiny
    var showsPrompt = true
    /// Whether this page should hold a player at all. `ClipDeckReview` sets it
    /// false for pages you aren't looking at: a paged `TabView` keeps every
    /// page it has built, and a story with fifteen clips in it would otherwise
    /// mean fifteen looping `AVPlayer`s alive at once.
    var isLive = true
    let url: URL
    let recordedAt: Date?
    var challengeID: UUID?
    var targetAuthorID: String?
    let onReRecord: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account

    /// Center caption editing, right on the video — same gesture as at
    /// record time. Saved to the card on submit/focus-out.
    @State private var captionDraft = ""
    @State private var editingCaption = false
    /// The finger's translation while a sticker is being dragged, in points.
    /// Only ever this — the card stores fractions, so nothing outlives the
    /// gesture that would have to be converted back.
    @State private var captionDrag: CGSize = .zero
    @FocusState private var captionFocused: Bool
    @State private var showComments = false
    @State private var showLook = false
    /// Held down in the look panel: play the clip as it was filmed.
    @State private var showingOriginal = false

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// How soft you want to look. Read here rather than passed in, because it's
    /// a setting about you and not about this clip — every clip you look back
    /// at gets the same one, and the film you save gets it too.
    @AppStorage(PersonalEffectParameters.storageKey) private var look: PersonalEffectParameters = .none
    @AppStorage(PersonalEffectParameters.stickyKey) private var lookIsSticky = false

    /// What the player should actually show. Holding the compare chip down puts
    /// the original back without touching what you've chosen.
    private var playedLook: PersonalEffectParameters { showingOriginal ? .none : look }

    private var myID: String { account.account?.id ?? "local" }

    private var card: DayCard? {
        guard let challengeID else { return nil }
        return store.challenge(challengeID)?.cards.first { $0.day == day }
    }

    private var interactions: (reactions: [ClipReaction], comments: [ClipComment]) {
        guard let challengeID else { return ([], []) }
        return store.interactions(for: challengeID, day: day, targetAuthorID: targetAuthorID ?? myID)
    }

    private var reactions: [ClipReaction] { interactions.reactions }
    private var comments: [ClipComment] { interactions.comments }

    /// Whether anyone else can see this clip.
    ///
    /// The gate used to be `challengeID != nil` — which is true of every story,
    /// shared or not. So filming a day by yourself and looking back at it put an
    /// empty "Add a comment…" box under your own face, waiting for you to talk
    /// to yourself, and a row of emoji nobody would ever see.
    private var isShared: Bool {
        guard let challengeID else { return false }
        return store.challenge(challengeID)?.isShared ?? false
    }

    /// The shape of the file, measured once it's readable.
    ///
    /// The story's own orientation only says how it was *filmed*, and a
    /// stitched moment isn't the shape of the takes inside it: two portrait
    /// takes side by side come out 9:8. Playing that edge to edge — which is
    /// right for one portrait take, and what this screen used to do to
    /// everything a portrait story contained — scaled it up until only the
    /// middle quarter of its width was on screen, so what you saw of two
    /// friends was the seam between them.
    @State private var measuredAspect: CGFloat?

    private var isLandscape: Bool {
        guard let challengeID else { return false }
        return store.challenge(challengeID)?.resolvedOrientation == .landscape
    }

    private var aspectRatio: CGFloat { measuredAspect ?? (isLandscape ? 16 / 9 : 9 / 16) }

    /// Edge to edge is for footage taller than it is wide, where filling the
    /// screen costs a strip off each side. Anything squarer than that keeps its
    /// own shape and sits on a blurred bed of itself.
    private var fillsScreen: Bool { aspectRatio < 0.95 }

    /// Whether this clip is mine to change.
    private var isMine: Bool {
        targetAuthorID == nil || targetAuthorID == "local" || targetAuthorID == myID
    }

    /// Only my page may read my live card. A friend's caption belongs to the
    /// displayed clip; a cleared own caption must not revive the deck snapshot.
    private var liveOverlayText: String? {
        ClipCaptionSelection.text(isMine: isMine, hasLiveCard: card != nil,
                                  liveText: card?.overlayText, snapshotText: overlayText)
    }
    private var hasCaption: Bool { !(liveOverlayText ?? "").isEmpty }

    /// Where the caption sits and how it's drawn.
    ///
    /// Read by the same rule as the words themselves: my own live card wins on
    /// my own page, a friend's belongs to the clip that was handed in, and a
    /// card nobody has dragged has no sticker at all — which is the default
    /// one, the place and style every caption used to be burned at, so nothing
    /// moves under somebody opening an old story.
    private var sticker: CaptionSticker {
        let live = isMine && card != nil
        return (live ? card?.captionSticker : captionSticker) ?? .default
    }

    private func saveSticker(_ new: CaptionSticker) {
        guard let challengeID else { return }
        store.updateCaptionSticker(new, day: day, challengeID: challengeID)
    }

    /// Which of the three styles the button is offering to switch to.
    private var styleSymbol: String {
        switch sticker.style {
        case .outline: "textformat.size.smaller"
        case .band: "textformat.size.larger"
        case .headline: "character"
        }
    }

    private func cycleCaptionStyle() {
        let styles = CaptionSticker.Style.allCases
        let next = styles[((styles.firstIndex(of: sticker.style) ?? 0) + 1) % styles.count]
        saveSticker(CaptionSticker(x: sticker.x, y: sticker.y, style: next))
    }

    private var localizedMomentTitle: String {
        slotTitle.map { MomentCatalog.localize($0) } ?? Strings.dayN(day)
    }

    private var displayLocale: Locale {
        Locale(identifier: appLanguage.resolved.localeCode)
    }

    private var timeText: String? {
        recordedAt?.formatted(.dateTime.hour().minute().locale(displayLocale))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            videoStage
            scrim
            if editingCaption {
                EmptyView()
            } else if showLook {
                lookOverlay
            } else {
                chrome
            }
        }
        .statusBarHidden()
        .task(id: url) { measuredAspect = await ClipGeometry.aspect(of: url) }
        .sheet(isPresented: $showComments) { commentsSheet }
        .onChange(of: captionFocused) { _, focused in
            if !focused, editingCaption { saveCaption() }
        }
        .onSubmit { captionFocused = false }
    }

    // MARK: - The video, and the one thing drawn where the film draws it

    /// The player plus the caption layer, sized to the video itself.
    ///
    /// Portrait footage goes edge to edge — `LoopingClipPlayer` already fills
    /// its frame, so a selfie crops at the sides rather than sitting in a
    /// letterbox. A wider film can't: filling a portrait screen with it would
    /// throw away most of the picture, so it keeps its shape. What used to be
    /// black bars either side of it is now the film's own first frame, blurred
    /// — the same idea the stitcher uses inside a cell, for the same reason.
    @ViewBuilder
    private var videoStage: some View {
        let stage = ZStack {
            if isLive {
                // Review is the truth: show the captured file without the personal look.
                // The look belongs in the dedicated adjustment/export surface.
                LoopingClipPlayer(url: url, refreshToken: recordedAt, look: .none)
            } else {
                Color.black
            }
            captionLayer
        }

        if fillsScreen {
            stage.ignoresSafeArea()
        } else {
            ZStack {
                backdrop
                stage.aspectRatio(aspectRatio, contentMode: .fit)
            }
        }
    }

    /// Behind a film that doesn't fill the screen: itself, out of focus.
    ///
    /// Bedded on `Color.clear` rather than framed, because a filling image
    /// reports the size it filled to and `.clipped()` only clips the drawing.
    /// A stitched moment is 9:8, so the bed measured a screen's height times
    /// 1.125 — 1078pt on a 440pt phone — and a ZStack lays its siblings out in
    /// the width of its widest child. That dragged the whole of `chrome` out
    /// with it: the caption button stretched to 749pt and "重拍" and "聊天"
    /// were placed past the right edge of the screen, present and untappable.
    /// `Color.clear` takes the offered size and overlays don't feed back into
    /// it, so the bed can overflow without moving anything else.
    private var backdrop: some View {
        Color.clear
            .overlay { ClipThumbnail(url: url, refreshToken: recordedAt) }
            .clipped()
            .blur(radius: 44)
            .overlay(Color.black.opacity(0.35))
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// The caption, wherever it was put.
    ///
    /// A sticker, not a fixed line: `VideoStitcher.captionLayer` burns it at the
    /// same fractions of the frame, in the same three styles, at the same size
    /// relative to the frame. That parity is why this lives inside
    /// `videoStage` rather than up in the chrome — it's part of the picture,
    /// not part of the interface — and why the numbers here are fractions of
    /// `proxy.size` rather than points.
    ///
    /// Tap edits the words. Drag moves them. Tapping anywhere else does
    /// nothing, which is the fix: the old edit button was `.frame(maxWidth:
    /// .infinity, maxHeight: .infinity)`, so the whole video was a button into
    /// the text editor.
    @ViewBuilder
    private var captionLayer: some View {
        if editingCaption {
            ZStack {
                // Somewhere to tap that means "done". The only other way out
                // was the keyboard's return key, which on a phone is a key you
                // have to know is there — and it's the key you press by
                // accident, so it can't be the only one that commits.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { captionFocused = false }
                CaptionOverlayEditor(text: $captionDraft, isFocused: $captionFocused)
            }
        } else if let text = liveOverlayText, !text.isEmpty {
            GeometryReader { proxy in
                captionText(text, in: proxy.size)
                    .frame(maxWidth: proxy.size.width * 0.76)
                    .contentShape(Rectangle())
                    .onTapGesture { if isMine { startEditingCaption() } }
                    .position(
                        x: (sticker.x + dragFraction(in: proxy.size).x) * proxy.size.width,
                        y: (sticker.y + dragFraction(in: proxy.size).y) * proxy.size.height)
                    .gesture(isMine ? dragSticker(in: proxy.size) : nil)
                    .animation(nil, value: captionDrag)
            }
        }
    }

    /// What the live drag is worth, as a fraction of the frame, so the sticker
    /// keeps up with the finger without a point-sized offset being stored
    /// anywhere: the model only ever holds fractions.
    private func dragFraction(in size: CGSize) -> (x: Double, y: Double) {
        guard size.width > 0, size.height > 0 else { return (0, 0) }
        return (captionDrag.width / size.width, captionDrag.height / size.height)
    }

    private func dragSticker(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { captionDrag = $0.translation }
            .onEnded { value in
                let moved = dragFraction(in: size)
                captionDrag = .zero
                guard abs(value.translation.width) + abs(value.translation.height) > 2
                else { return }
                saveSticker(CaptionSticker(
                    x: sticker.x + moved.x, y: sticker.y + moved.y, style: sticker.style))
            }
    }

    /// Same fractions, weights and shadow the stitcher uses, so what you read
    /// here is what gets exported.
    private func captionText(_ text: String, in size: CGSize) -> some View {
        let minEdge = min(size.width, size.height)
        let fontSize = minEdge * (sticker.style == .headline ? 0.092 : 0.062)
        return Text(text)
            .font(.system(
                size: fontSize,
                weight: sticker.style == .headline ? .heavy : .bold,
                design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.68)
            .padding(.horizontal, sticker.style == .band ? fontSize * 0.8 : 0)
            .padding(.vertical, sticker.style == .band ? fontSize * 0.42 : 0)
            .background {
                if sticker.style == .band {
                    RoundedRectangle(cornerRadius: fontSize * 0.7, style: .continuous)
                        .fill(.black.opacity(0.45))
                }
            }
            .shadow(
                color: .black.opacity(sticker.style == .band ? 0 : 0.28),
                radius: 5, y: 2)
    }

    private var scrim: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.42), .clear, .clear, .black.opacity(0.62),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            top
            Spacer(minLength: 0)
            bottom
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }

    private var top: some View {
        ZStack {
            positionChip
            HStack {
                IconBubble(systemName: "xmark") { dismiss() }
                Spacer(minLength: 0)
                // Up here rather than down with the caption and retake buttons,
                // because it isn't a thing you do to this clip — it's how you
                // want to see all of them.
                IconBubble(systemName: look.isIdentity ? "camera.filters" : "sparkles") {
                    withAnimation(OneDay.Motion.soft) { showLook = true }
                }
            }
        }
    }

    /// The look panel, over the clip it's changing.
    private var lookOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LookPanel(
                look: $look, sticky: $lookIsSticky, showingOriginal: $showingOriginal
            ) {
                withAnimation(OneDay.Motion.soft) { showLook = false }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Where you are in the story.
    ///
    /// The moment's name used to be in the navigation bar's title and its
    /// *number* was printed across the middle of the video, so the screen said
    /// "MOMENT 4" over someone's face while "Golden hour" sat in a white bar at
    /// the top. One chip, above the picture, says both.
    ///
    /// Whose clip it is belongs at the bottom next to the time, not here — a
    /// name is about the person, and the person is in the picture.
    @ViewBuilder
    private var positionChip: some View {
        let parts = [
            momentCount > 0 ? "\(day) / \(momentCount)" : nil,
            showsPrompt ? localizedMomentTitle : nil,
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: "  ·  "))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.black.opacity(0.34), in: Capsule())
                .padding(.horizontal, 54)
        }
    }

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Only somebody else's name. Labelling your own face with your own
            // name is the kind of thing an app does when it forgot who's
            // holding it.
            if !isMine, let authorName, !authorName.isEmpty {
                Text(authorName)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
            }
            if let timeText {
                Text(timeText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }

            if isShared {
                ReactionBar(reactions: reactions, myID: myID) { emoji in
                    if let challengeID {
                        store.toggleReaction(
                            emoji, day: day, challengeID: challengeID,
                            targetAuthorID: targetAuthorID ?? myID)
                    }
                }
            }

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack(spacing: 9) {
            if isMine {
                floatingButton(
                    hasCaption ? "textformat" : "text.badge.plus",
                    Strings.captionAction,
                    fills: true,
                    action: startEditingCaption)
                // Only once there are words to restyle, and with no label: the
                // caption itself is the label, and it changes in place as this
                // is tapped. A panel for three options would be a panel you
                // have to close before you can see what you picked.
                if hasCaption {
                    floatingButton(styleSymbol, nil, action: cycleCaptionStyle)
                }
                floatingButton("arrow.counterclockwise", Strings.rerecordShort, action: onReRecord)
            }
            if isShared {
                floatingButton(
                    "bubble.left.fill",
                    appLanguage.resolved == .chinese ? "聊天" : "Chat",
                    fills: !isMine
                ) { showComments = true }
            }
        }
    }

    private func floatingButton(
        _ symbol: String, _ title: String?, fills: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                if let title {
                    Text(title)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(OneDay.ink)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: fills ? .infinity : nil)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Comments

    /// The thread, on request.
    ///
    /// It was an inline list under the video, which meant a clip with eight
    /// comments on it pushed the clip off the screen — the one thing you opened
    /// this screen to look at. In a sheet the video stays behind it, still
    /// looping.
    private var commentsSheet: some View {
        Group {
            if let challengeID {
                RoomChatView(challengeID: challengeID, moment: day)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.oneDayMist)
    }

    // MARK: - Caption

    private func startEditingCaption() {
        captionDraft = liveOverlayText ?? ""
        editingCaption = true
        captionFocused = true
    }

    private func saveCaption() {
        editingCaption = false
        guard let challengeID else { return }
        store.updateOverlayText(captionDraft, day: day, challengeID: challengeID)
    }
}
