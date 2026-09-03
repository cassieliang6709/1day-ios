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
    @FocusState private var captionFocused: Bool
    @State private var showComments = false

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

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

    private var isLandscape: Bool {
        guard let challengeID else { return false }
        return store.challenge(challengeID)?.resolvedOrientation == .landscape
    }

    private var aspectRatio: CGFloat { isLandscape ? 16 / 9 : 9 / 16 }

    /// Whether this clip is mine to change.
    private var isMine: Bool {
        targetAuthorID == nil || targetAuthorID == "local" || targetAuthorID == myID
    }

    /// Prefer the live card's caption so edits show immediately; fall back to
    /// the value passed in (used when there's no challenge context).
    private var liveOverlayText: String? { card?.overlayText ?? overlayText }
    private var hasCaption: Bool { !(liveOverlayText ?? "").isEmpty }

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
            if !editingCaption { chrome }
        }
        .statusBarHidden()
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
    /// letterbox. Landscape footage can't: filling a portrait screen with a
    /// 16:9 frame would throw away most of the picture, so it keeps its bars.
    @ViewBuilder
    private var videoStage: some View {
        let stage = ZStack {
            if isLive {
                LoopingClipPlayer(url: url, refreshToken: recordedAt)
            } else {
                Color.black
            }
            captionLayer
        }

        if isLandscape {
            stage.aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            stage.ignoresSafeArea()
        }
    }

    /// The caption, at 43% down the frame.
    ///
    /// That number is not a design choice — `VideoStitcher.addOverlayText`
    /// burns the caption in at `height * 0.43`, centered. This is the one piece
    /// of this screen that has to match the film exactly, which is also why it
    /// belongs inside `videoStage` rather than up in the chrome: it's part of
    /// the picture, not part of the interface.
    ///
    /// Tapping the caption edits it. Tapping anywhere else does nothing, which
    /// is the fix: the old edit button was `.frame(maxWidth: .infinity,
    /// maxHeight: .infinity)`, so the whole video was a button into the text
    /// editor — and its label sat in the dead center, printed straight on top
    /// of the "MOMENT 4" that `MomentStampOverlay` drew in the same spot.
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
                captionText(text)
                    .frame(maxWidth: proxy.size.width * 0.76)
                    .contentShape(Rectangle())
                    .onTapGesture { if isMine { startEditingCaption() } }
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.43)
            }
        }
    }

    /// Same size, weight and shadow the stitcher uses, so what you read here is
    /// what gets exported.
    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.68)
            .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
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
            }
        }
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
                floatingButton("arrow.counterclockwise", Strings.rerecordShort, action: onReRecord)
            }
            if isShared {
                floatingButton(
                    "bubble.left.fill",
                    comments.isEmpty ? nil : "\(comments.count)",
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
        NavigationStack {
            ScrollView {
                CommentsSection(comments: comments, myID: myID) { comment in
                    if let challengeID {
                        store.deleteComment(
                            comment.id, day: day, challengeID: challengeID,
                            targetAuthorID: targetAuthorID ?? myID)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(
                comments.isEmpty ? Strings.comments : Strings.commentsCount(comments.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { showComments = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                CommentInputBar { text in
                    if let challengeID {
                        store.addComment(
                            text, day: day, challengeID: challengeID,
                            targetAuthorID: targetAuthorID ?? myID)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Without this the sheet is translucent over a playing video, so the
        // thread reads as grey text on whatever colour is on screen this frame.
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
