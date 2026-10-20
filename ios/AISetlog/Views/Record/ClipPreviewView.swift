import SwiftUI

/// One person's one take, full screen, and the place its captions are written.
///
/// Tapping any clip — a tile in a room, a clip in 我的 — opens this: the video
/// edge to edge, the captions on the video itself where the film burns them,
/// and the buttons floating over the bottom of the picture.
///
/// It replaces two screens. A room's tile used to open the whole moment with
/// everyone stitched together (`StitchedMomentPreview`), where nothing could be
/// edited, and 我的 opened a half-height sheet that played the day in a row
/// (`LibraryDayPlayer`) with a separate editor one more tap away. Both answered
/// "what does this moment look like"; what people tapped a clip for was to do
/// something to it.
///
/// A take can carry several captions (`Caption`). Each is its own sticker:
/// tap once to select it (the handles and the ✕ appear, and the colour and
/// backing rows under the picture apply to it), tap again to type, drag to
/// move, pinch or use the corner to size and turn. 加字幕 always adds another.
///
/// The picture is fitted, not filled. A caption is placed as a fraction of the
/// exported frame, so cropping the video to fill the screen would mean aiming
/// at a picture that is not the one the film is made of — a caption put near
/// the edge would land somewhere nobody could see while placing it. A 9:16
/// take on a phone fills the width and nearly all the height anyway.
struct ClipPreviewView: View {
    /// Something this screen can offer for the clip on it that isn't about the
    /// clip's captions — 放进故事 or 打开故事 from 我的, say. Destructive ones go
    /// in the ⋯ menu, the rest sit in the button row.
    struct ExtraAction: Identifiable {
        /// Doubles as the accessibility identifier.
        let id: String
        let symbol: String
        let title: String
        var isDestructive = false
        let action: () -> Void
    }

    let day: Int
    var slotTitle: String?
    /// How many moments the story has, for the "4 / 5" chip. 0 hides the count
    /// — a clip opened without its story behind it has no denominator.
    var momentCount = 0
    var authorName: String?
    /// The clip's captions as they were handed in, for a clip this screen
    /// can't read a live card for — a friend's take, or a draft.
    var captions: [Caption] = []
    var clipLength: Challenge.ClipLength = .tiny
    var showsPrompt = true
    /// Whether this page should hold a player at all.
    var isLive = true
    let url: URL
    let recordedAt: Date?
    var challengeID: UUID?
    var targetAuthorID: String?
    /// Which of my takes of this moment this is; nil is take 1. Caption edits
    /// go to that take, and its words are read from it — not from the card's
    /// own fields, which are take 1's.
    var takeID: UUID? = nil
    /// Nil hides 重拍: replaying a clip from 我的 has no camera to go back to.
    /// 重拍 replaces this take; the caller knows which one that is.
    let onReRecord: (() -> Void)?
    /// 再拍一段: film this moment again and keep both. Nil hides it, for the
    /// same reason as 重拍.
    var onAddTake: (() -> Void)? = nil
    /// A clip in no story (one only you can see in 我的) has no card to write
    /// its captions to; this takes them instead.
    var onDraftCaptions: (([Caption]) -> Void)? = nil
    var extraActions: [ExtraAction] = []

    /// The draft's captions as edited here, shown in place of `captions`.
    @State private var draftCaptions: [Caption]?

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account

    /// The caption that is selected: handles drawn, the style rows aimed at it.
    ///
    /// Two taps rather than one to type, because one tap has to keep meaning
    /// "let me see the handles". Dragging, pinching and twisting a caption all
    /// worked before selection existed and nothing on screen said so.
    @State private var selectedID: UUID?
    /// Typing, right on the video — same gesture as at record time.
    @State private var editingCaption = false
    /// Which caption is being typed into. A new one isn't in the list yet.
    @State private var editingID: UUID?
    @State private var editingIsNew = false
    @State private var captionDraft = ""
    /// Whether a drag is currently held on the frame's middle.
    @State private var snappedToCentre = false
    /// Shown under the caption the first time one is selected, then never again.
    @AppStorage("caption.gestureHintSeen.v1") private var gestureHintSeen = false
    @FocusState private var captionFocused: Bool
    @State private var showComments = false
    @State private var showLook = false
    /// Held down in the look panel: play the clip as it was filmed.
    @State private var showingOriginal = false
    /// The caption the ✕ just took off, and where it was, for the undo toast.
    @State private var deleted: DeletedCaption?

    private struct DeletedCaption: Equatable {
        let caption: Caption
        let index: Int
    }

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// How soft you want to look. A setting about you, not about this clip.
    @AppStorage(PersonalEffectParameters.storageKey) private var look: PersonalEffectParameters = .none
    @AppStorage(PersonalEffectParameters.stickyKey) private var lookIsSticky = false

    private var playedLook: PersonalEffectParameters { showingOriginal ? .none : look }

    private var myID: String { account.account?.id ?? "local" }

    private var card: DayCard? {
        guard let challengeID else { return nil }
        return store.challenge(challengeID)?.cards.first { $0.day == day }
    }

    /// The live take this page shows, when it is one of the extra ones.
    private var extraTake: ClipTake? {
        guard let takeID else { return nil }
        return card?.moreTakes.first { $0.id == takeID }
    }

    private var comments: [ClipComment] {
        guard let challengeID else { return [] }
        return store.interactions(
            for: challengeID, day: day, targetAuthorID: targetAuthorID ?? myID).comments
    }

    /// Whether anyone else can see this clip. A story you film alone has no
    /// thread to open.
    private var isShared: Bool {
        guard let challengeID else { return false }
        return store.challenge(challengeID)?.isShared ?? false
    }

    /// The shape of the file, measured once it's readable — a stitched or
    /// landscape take isn't the shape its story was filmed in.
    @State private var measuredAspect: CGFloat?

    private var isLandscape: Bool {
        guard let challengeID else { return false }
        return store.challenge(challengeID)?.resolvedOrientation == .landscape
    }

    private var aspectRatio: CGFloat { measuredAspect ?? (isLandscape ? 16 / 9 : 9 / 16) }

    /// Whether this clip is mine to change.
    private var isMine: Bool {
        targetAuthorID == nil || targetAuthorID == "local" || targetAuthorID == myID
    }

    /// Somewhere for an edit to go.
    private var canWrite: Bool { challengeID != nil || onDraftCaptions != nil }

    /// Every caption on this take, as it stands now.
    ///
    /// Only my page reads my live card. A friend's captions belong to the clip
    /// that was handed in, and an own card whose captions were all deleted
    /// must not bring the handed-in snapshot back.
    private var liveCaptions: [Caption] {
        if onDraftCaptions != nil { return draftCaptions ?? captions }
        if takeID != nil {
            return ClipCaptionSelection.captions(
                isMine: isMine, hasLiveCard: extraTake != nil,
                live: extraTake?.captions ?? [], snapshot: captions)
        }
        return ClipCaptionSelection.captions(
            isMine: isMine, hasLiveCard: card != nil,
            live: card?.captions ?? [], snapshot: captions)
    }

    /// Where an edit goes: the story's card (and from there the room), or the
    /// draft.
    private func writeCaptions(_ list: [Caption]) {
        let kept = list.drawable
        if let onDraftCaptions {
            draftCaptions = kept
            onDraftCaptions(kept)
        } else if let challengeID {
            store.updateCaptions(kept, day: day, challengeID: challengeID, takeID: takeID)
        }
    }

    /// What the colour and backing rows change: the selected caption, or the
    /// only one when there is only one.
    private var target: Caption? {
        let list = liveCaptions.drawable
        if let selectedID, let hit = list.first(where: { $0.id == selectedID }) { return hit }
        return list.count == 1 ? list.first : nil
    }

    private func saveSticker(_ sticker: CaptionSticker, for id: UUID) {
        var list = liveCaptions
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].sticker = sticker
        writeCaptions(list)
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
            backdrop
            stage
            scrims
            if editingCaption { outsideTapCatcher }
            chrome
            if showLook { lookOverlay }
            if deleted != nil { undoToast }
        }
        .statusBarHidden()
        // The keyboard covers the bottom of this screen rather than resizing
        // it: the picture must not jump to a different size the moment you
        // start typing on it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: url) { measuredAspect = await ClipGeometry.aspect(of: url) }
        .sheet(isPresented: $showComments) { commentsSheet }
        .onChange(of: captionFocused) { _, focused in
            if !focused, editingCaption { saveCaption() }
        }
        .onSubmit { commitCaption() }
        .onChange(of: captionDraft) { _, new in limitCaptionLines(new) }
    }

    /// While typing, a tap anywhere off the picture means "done".
    private var outsideTapCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture { commitCaption() }
    }

    // MARK: - The video

    /// The take, as big as the screen allows at its own shape, with the
    /// captions drawn inside it.
    ///
    /// `Color.clear` sized by the aspect ratio rather than the player itself:
    /// a player reports the size it filled to, and an overlay can't feed back
    /// into the layout around it.
    private var stage: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { videoStage }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .accessibilityIdentifier("moment-stage")
    }

    /// The player plus the caption layer.
    private var videoStage: some View {
        ZStack {
            if isLive {
                // Review is the truth: no personal look, except while the look
                // panel is up — that panel promises the picture changes.
                LoopingClipPlayer(
                    url: url, refreshToken: recordedAt,
                    look: showLook ? playedLook : .none)
            } else {
                Color.black
            }
            captionLayer
        }
    }

    /// Behind a take that doesn't fill the screen: itself, out of focus.
    private var backdrop: some View {
        Color.clear
            .overlay { ClipThumbnail(url: url, refreshToken: recordedAt) }
            .clipped()
            .blur(radius: 44)
            .overlay(Color.black.opacity(0.5))
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// Dark at the top and bottom edges, so white buttons read over a bright
    /// picture. Only there: the middle is the picture.
    private var scrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
                .opacity(editingCaption ? 0 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Every caption, wherever it was put.
    ///
    /// Inside `videoStage` because it's part of the picture, not part of the
    /// interface: `VideoStitcher.captionLayer` burns each one at the same
    /// fractions of the frame, in the same styles, at the same size relative to
    /// the frame.
    @ViewBuilder
    private var captionLayer: some View {
        if editingCaption {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { captionFocused = false }
                CaptionOverlayEditor(text: $captionDraft, isFocused: $captionFocused)
            }
        } else {
            let list = liveCaptions.drawable
            if !list.isEmpty {
                GeometryReader { proxy in
                    ZStack {
                        // Tapping the picture puts the handles away. Only while
                        // something is selected: the rest of the time this layer
                        // must not eat taps meant for the video underneath.
                        if selectedID != nil {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { deselectCaption() }
                            if snappedToCentre { centreGuide }
                        }

                        ForEach(list) { caption in
                            CaptionStickerView(
                                caption: caption,
                                stageSize: proxy.size,
                                isSelected: selectedID == caption.id,
                                isMine: isMine,
                                snappedToCentre: $snappedToCentre,
                                onTap: { tapCaption(caption.id) },
                                onChange: { saveSticker($0, for: caption.id) },
                                onDelete: { deleteCaption(caption.id) })
                        }

                        if selectedID != nil, isMine, !gestureHintSeen { gestureHint }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .coordinateSpace(name: CaptionStickerView.stageSpace)
                    .sensoryFeedback(.alignment, trigger: snappedToCentre) { _, now in now }
                }
            }
        }
    }

    /// The middle of the frame, drawn only while a sticker is held on it.
    private var centreGuide: some View {
        Rectangle()
            .fill(.white.opacity(0.85))
            .frame(width: 1)
            .padding(.vertical, 12)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private var gestureHint: some View {
        VStack {
            Spacer(minLength: 0)
            Text(Strings.captionGestureHint)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 12)
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("caption-gesture-hint")
    }

    // MARK: - Chrome

    /// The top bar and the bottom controls, floating over the picture. The
    /// `Spacer` between them takes no taps, so the captions underneath it stay
    /// reachable.
    private var chrome: some View {
        VStack(spacing: 0) {
            top
                .padding(.horizontal, 14)
                .padding(.top, 8)
            Spacer(minLength: 0)
            bottomControls
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }

    /// Who and when, the selected caption's colour and backing, then the
    /// buttons.
    ///
    /// Faded rather than removed while typing, so nothing above it moves.
    private var bottomControls: some View {
        VStack(spacing: 9) {
            byline
            if isMine, let target {
                tintRows(for: target)
                plateRow(for: target)
            }
            buttonRow
        }
        .opacity(editingCaption ? 0 : 1)
        .allowsHitTesting(!editingCaption)
        .animation(OneDay.Motion.soft, value: editingCaption)
    }

    /// Whose moment it is, and when it was filmed.
    private var byline: some View {
        HStack(spacing: 8) {
            // Only somebody else's name. Labelling your own face with your own
            // name is the kind of thing an app does when it forgot who's
            // holding it.
            Text(isMine ? Strings.thisMoment : (authorName ?? Strings.thisMoment))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 4)
            if let timeText {
                Text(timeText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
    }

    /// Twelve colours, two rows of six, all on screen.
    private func tintRows(for caption: Caption) -> some View {
        let sticker = caption.placed
        return VStack(spacing: 7) {
            ForEach(Array(tintPages.enumerated()), id: \.offset) { _, page in
                HStack(spacing: 7) {
                    ForEach(page) { tint in
                        Button {
                            saveSticker(
                                sticker.reshaped(
                                    style: CaptionSticker.legibleStyle(
                                        picking: tint, keeping: sticker.style),
                                    tint: tint),
                                for: caption.id)
                        } label: {
                            Circle()
                                .fill(tint.color)
                                .frame(height: 26)
                                .frame(maxWidth: .infinity)
                                .overlay {
                                    // White for the edge every dot needs against
                                    // footage, blue outside it for the chosen one.
                                    Circle()
                                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                                        .frame(width: 26, height: 26)
                                    if tint == sticker.tint {
                                        Circle()
                                            .strokeBorder(Color.oneDayBrand, lineWidth: 2.5)
                                            .frame(width: 33, height: 33)
                                    }
                                }
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Strings.captionTintName(tint))
                        .accessibilityAddTraits(tint == sticker.tint ? .isSelected : [])
                    }
                }
            }
        }
        .accessibilityIdentifier("caption-tints")
    }

    /// Six per row, in the order `Tint` declares them.
    private var tintPages: [[CaptionSticker.Tint]] {
        let all = CaptionSticker.Tint.allCases
        return stride(from: 0, to: all.count, by: 6).map {
            Array(all[$0..<min($0 + 6, all.count)])
        }
    }

    /// The four backings, drawn as what they are: 字 in the caption's own
    /// colour on the backing tapping it would give.
    private func plateRow(for caption: Caption) -> some View {
        let sticker = caption.placed
        return HStack(spacing: 7) {
            ForEach(CaptionSticker.Style.picker) { style in
                let chosen = style == sticker.style.pickerEquivalent
                let sample = CaptionSticker(
                    x: 0.5, y: 0.5, style: style,
                    tint: CaptionSticker.legibleTint(
                        picking: style, keeping: sticker.tint))
                Button {
                    saveSticker(sticker.reshaped(style: style, tint: sample.tint), for: caption.id)
                } label: {
                    Text(Strings.captionPlateSample)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(sample.tint.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if let fill = sample.plateColor, let plate = style.plate {
                                RoundedRectangle(
                                    cornerRadius: 30 * plate.radius, style: .continuous
                                )
                                .fill(fill)
                            } else {
                                // "No backing" has to look like no backing: a
                                // faint fill and a dashed edge.
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.white.opacity(0.1))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(
                                                .white.opacity(0.4),
                                                style: StrokeStyle(lineWidth: 1, dash: [3.5, 3]))
                                    }
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    chosen
                                        ? AnyShapeStyle(Color.oneDayBrand)
                                        : AnyShapeStyle(.white.opacity(0.2)),
                                    lineWidth: chosen ? 2.5 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.captionPlateName(style))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .accessibilityIdentifier("caption-plates")
    }

    /// Everything you can do to this take, side by side.
    private var buttonRow: some View {
        HStack(spacing: 7) {
            if isMine, canWrite {
                actionButton(
                    "text.badge.plus", Strings.captionAction,
                    accented: !isShared,
                    identifier: "moment-caption",
                    action: startNewCaption)
            }
            if isMine {
                if let onReRecord {
                    actionButton(
                        "arrow.counterclockwise", Strings.rerecordShort,
                        accented: false, identifier: "moment-rerecord", action: onReRecord)
                }
                if let onAddTake {
                    actionButton(
                        "plus.rectangle.on.rectangle", Strings.addTakeShort,
                        accented: false, identifier: "moment-add-take", action: onAddTake)
                }
            }
            if isShared {
                // Accented in a room: what isn't obvious there is that a moment
                // has a thread on it at all.
                actionButton(
                    "bubble.left.fill", Strings.chatShort,
                    accented: true, identifier: "moment-chat",
                    badge: comments.isEmpty ? nil : comments.count
                ) { showComments = true }
            }
            ForEach(extraActions.filter { !$0.isDestructive }) { extra in
                actionButton(
                    extra.symbol, extra.title, accented: false,
                    identifier: extra.id, action: extra.action)
            }
        }
    }

    private func actionButton(
        _ symbol: String, _ title: String, accented: Bool, identifier: String,
        badge: Int? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accented ? OneDay.onBrand.opacity(0.85) : .white.opacity(0.7))
                }
            }
            // White on dark glass for the quiet ones: this row sits on the
            // picture, so it has to read over whatever the picture is.
            .foregroundStyle(accented ? OneDay.onBrand : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if accented {
                    Capsule().fill(OneDay.brandHorizontal)
                } else {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(.black.opacity(0.18))
                    }
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    .environment(\.colorScheme, .dark)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var top: some View {
        ZStack {
            positionChip
            HStack {
                IconBubble(systemName: "xmark", overVideo: true) { dismiss() }
                    .accessibilityLabel(Strings.close)
                    .accessibilityIdentifier("moment-close")
                Spacer(minLength: 0)
                topTrailing
            }
        }
    }

    /// 完成 while a caption is being typed; otherwise the look button on
    /// somebody else's clip, and the ⋯ menu when there is something in it.
    @ViewBuilder
    private var topTrailing: some View {
        if editingCaption {
            Button(action: commitCaption) {
                Text(Strings.done)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.onBrand)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(OneDay.brandHorizontal))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("caption-done")
        } else {
            HStack(spacing: 8) {
                if !isMine {
                    IconBubble(
                        systemName: look.isIdentity ? "camera.filters" : "sparkles",
                        overVideo: true
                    ) {
                        withAnimation(OneDay.Motion.soft) { showLook = true }
                    }
                    .accessibilityLabel(Strings.lookTitle)
                }
                let destructive = extraActions.filter(\.isDestructive)
                if !destructive.isEmpty {
                    Menu {
                        ForEach(destructive) { extra in
                            Button(role: .destructive, action: extra.action) {
                                Label(extra.title, systemImage: extra.symbol)
                            }
                            .accessibilityIdentifier(extra.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.32), in: Circle())
                    }
                    .accessibilityLabel(Strings.moreLabel)
                    .accessibilityIdentifier("moment-more")
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

    /// Where you are in the story: 「4 / 5 · Golden hour」.
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

    // MARK: - Comments

    /// The thread, on request, in a sheet over the still-looping take.
    private var commentsSheet: some View {
        Group {
            if let challengeID {
                RoomChatView(
                    challengeID: challengeID,
                    moment: day,
                    reactionTarget: .init(day: day, authorID: targetAuthorID ?? myID))
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.oneDayMist)
    }

    // MARK: - Caption editing

    /// 加字幕: a new caption, typed straight onto the picture. It lands below
    /// the ones already there rather than on top of them.
    private func startNewCaption() {
        guard canWrite else { return }
        captionDraft = ""
        editingID = UUID()
        editingIsNew = true
        beginTyping()
    }

    private func startEditing(_ id: UUID) {
        guard let caption = liveCaptions.first(where: { $0.id == id }) else { return }
        captionDraft = caption.text
        editingID = id
        editingIsNew = false
        beginTyping()
    }

    private func beginTyping() {
        editingCaption = true
        captionFocused = true
        // The handles have no business being on screen behind a keyboard.
        selectedID = nil
    }

    private func saveCaption() {
        editingCaption = false
        guard canWrite, let id = editingID else { return }
        // A Return pressed at the end leaves a trailing newline; the burned
        // caption shouldn't carry an empty second line.
        let text = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        captionDraft = ""
        editingID = nil
        var list = liveCaptions
        if editingIsNew {
            guard !text.isEmpty else { return }
            list.append(Caption(id: id, text: text, sticker: Self.placement(after: list)))
        } else if let i = list.firstIndex(where: { $0.id == id }) {
            if text.isEmpty {
                list.remove(at: i)
            } else {
                list[i].text = text
            }
        }
        writeCaptions(list)
    }

    /// Where a new caption goes. The first one sits where every caption always
    /// has; each one after drops into a free band of the frame, in the look of
    /// the one before it, so two captions are never one pile of words.
    static func placement(after list: [Caption]) -> CaptionSticker? {
        let shown = list.drawable
        guard let last = shown.last?.placed else { return nil }
        let bands: [Double] = [0.62, 0.25, 0.78, 0.15, 0.5]
        let taken = shown.map(\.placed.y)
        let y = bands.first { band in taken.allSatisfy { abs($0 - band) > 0.1 } }
            ?? bands[shown.count % bands.count]
        return CaptionSticker(x: 0.5, y: y, style: last.style, tint: last.tint)
    }

    /// The one way out of the editor: 完成, a tap off the caption, Return on
    /// the second line, and focus leaving all end here.
    private func commitCaption() {
        captionFocused = false
        if editingCaption { saveCaption() }
    }

    /// Two lines at most, the same cap the burned caption has.
    private func limitCaptionLines(_ text: String) {
        guard editingCaption else { return }
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count > 2 else { return }
        captionDraft = String(parts[0]) + "\n" + parts[1...].joined()
        commitCaption()
    }

    /// First tap selects, second tap types.
    private func tapCaption(_ id: UUID) {
        guard isMine, canWrite else { return }
        if selectedID == id {
            gestureHintSeen = true
            startEditing(id)
        } else {
            withAnimation(OneDay.Motion.soft) { selectedID = id }
        }
    }

    private func deselectCaption() {
        withAnimation(OneDay.Motion.soft) { selectedID = nil }
        gestureHintSeen = true
    }

    /// The ✕ on a caption's box. Takes that one caption off; 撤销 in the toast
    /// puts it back where it was, in its place in the list.
    private func deleteCaption(_ id: UUID) {
        guard canWrite else { return }
        var list = liveCaptions
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let removed = DeletedCaption(caption: list.remove(at: i), index: i)
        writeCaptions(list)
        withAnimation(OneDay.Motion.soft) {
            deleted = removed
            selectedID = nil
        }
        gestureHintSeen = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if deleted == removed {
                withAnimation(OneDay.Motion.soft) { deleted = nil }
            }
        }
    }

    private var undoToast: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Text(Strings.captionDeleted)
                    .font(.subheadline.weight(.semibold))
                Button(Strings.undo) {
                    guard let deleted else { return }
                    var list = liveCaptions
                    list.insert(deleted.caption, at: min(deleted.index, list.count))
                    writeCaptions(list)
                    withAnimation(OneDay.Motion.soft) { self.deleted = nil }
                }
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color.oneDaySky)
                .frame(minHeight: 44)
                .accessibilityIdentifier("caption-undo")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .background(.black.opacity(0.75), in: Capsule())
            .padding(.bottom, 130)
        }
        .transition(.opacity)
    }
}

// MARK: - One caption on the picture

/// One caption, as a sticker: drawn where it was put, and moved, sized and
/// turned by hand.
///
/// Its own view so each caption keeps its own live gesture state — a pinch on
/// one must not grow the others. Like the old single sticker, it holds only the
/// gesture in flight; the committed value goes back through `onChange` as a
/// finished `CaptionSticker`, in fractions of the frame.
private struct CaptionStickerView: View {
    let caption: Caption
    let stageSize: CGSize
    let isSelected: Bool
    let isMine: Bool
    @Binding var snappedToCentre: Bool
    let onTap: () -> Void
    let onChange: (CaptionSticker) -> Void
    let onDelete: () -> Void

    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var twist: Double = 0
    @State private var handleScale: CGFloat = 1
    @State private var handleTwist: Double = 0

    /// The name the corner handle's drag measures itself in.
    static let stageSpace = "caption-stage"

    private var sticker: CaptionSticker { caption.placed }

    var body: some View {
        captionText
            // Inside the flexible frame and inside the scale and rotation, so
            // the box hugs the words at whatever size and angle they are.
            .overlay {
                if isSelected, isMine { selectionChrome }
            }
            .frame(maxWidth: stageSize.width * 0.76)
            .scaleEffect(pinch * handleScale)
            .rotationEffect(.degrees(sticker.angle + twist + handleTwist))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .position(
                x: (sticker.x + dragFraction.x) * stageSize.width,
                y: (sticker.y + dragFraction.y) * stageSize.height)
            .gesture(isMine ? shape : nil)
            .animation(nil, value: drag)
            .animation(nil, value: pinch)
            .animation(nil, value: twist)
            .animation(nil, value: handleScale)
            .animation(nil, value: handleTwist)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("caption-sticker")
    }

    /// Same fractions, weights and shadow the stitcher uses, so what you read
    /// here is what gets exported.
    private var captionText: some View {
        let minEdge = min(stageSize.width, stageSize.height)
        let base = minEdge * (sticker.style == .headline ? 0.092 : 0.062)
        let fontSize = base * sticker.scale
        return Text(caption.trimmedText ?? "")
            .font(.system(
                size: fontSize,
                weight: sticker.style == .headline ? .heavy : .bold,
                design: .rounded))
            .foregroundStyle(sticker.tint.color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.68)
            .padding(.horizontal, (sticker.style.plate?.padH ?? 0) * fontSize)
            .padding(.vertical, (sticker.style.plate?.padV ?? 0) * fontSize)
            .background {
                if let plate = sticker.style.plate, let fill = sticker.plateColor {
                    RoundedRectangle(
                        cornerRadius: fontSize * (1 + plate.padV * 2) * plate.radius,
                        style: .continuous
                    )
                    .fill(fill)
                }
            }
            .shadow(
                color: .black.opacity(sticker.style.plate == nil ? 0.28 : 0),
                radius: 5, y: 2)
            .accessibilityIdentifier("caption-text")
    }

    /// The dashed box, the three corners and the ✕.
    private var selectionChrome: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(
                .white.opacity(0.92),
                style: StrokeStyle(lineWidth: 1.2, dash: [4.5, 3.5]))
            .padding(-9)
            .overlay(alignment: .topLeading) {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color(uiColor: UIColor(hex: 0x0F2E6B)))
                        .frame(width: 20, height: 20)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        // Drawn at 20, hit at 44.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: -31, y: -31)
                .accessibilityLabel(Strings.deleteCaptionAction)
                .accessibilityIdentifier("caption-delete")
            }
            .overlay(alignment: .topTrailing) { handleDot.offset(x: 4, y: -14) }
            .overlay(alignment: .bottomLeading) { handleDot.offset(x: -14, y: 4) }
            .overlay(alignment: .bottomTrailing) {
                handleDot
                    .offset(x: 4, y: 4)
                    // The one corner that does something: the corner a right
                    // thumb reaches without covering the words.
                    .gesture(cornerDrag)
                    .accessibilityLabel(Strings.captionResizeHandle)
                    .accessibilityIdentifier("caption-handle")
            }
    }

    private var handleDot: some View {
        Circle()
            .fill(.white)
            .frame(width: 11, height: 11)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .contentShape(Circle().scale(2.6))
    }

    /// Drag, pinch and twist at once.
    private var shape: some Gesture {
        SimultaneousGesture(
            dragGesture,
            SimultaneousGesture(
                MagnifyGesture()
                    .onChanged { pinch = $0.magnification }
                    .onEnded { value in
                        pinch = 1
                        onChange(sticker.reshaped(scale: sticker.scale * value.magnification))
                    },
                RotateGesture()
                    .onChanged { twist = $0.rotation.degrees }
                    .onEnded { value in
                        twist = 0
                        onChange(sticker.reshaped(angle: sticker.angle + value.rotation.degrees))
                    }))
    }

    /// The live drag, as a fraction of the frame: the model only holds
    /// fractions.
    private var dragFraction: (x: Double, y: Double) {
        guard stageSize.width > 0, stageSize.height > 0 else { return (0, 0) }
        return (drag.width / stageSize.width, drag.height / stageSize.height)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard stageSize.width > 0 else {
                    drag = value.translation
                    return
                }
                // Snapping applies to the live translation too: a caption that
                // jumps into place only after the finger lifts reads as the app
                // moving it somewhere you didn't put it.
                let wanted = sticker.x + value.translation.width / stageSize.width
                if let snapped = CaptionGestureMath.snapToCentre(wanted) {
                    drag = CGSize(
                        width: (snapped - sticker.x) * stageSize.width,
                        height: value.translation.height)
                    snappedToCentre = true
                } else {
                    drag = value.translation
                    snappedToCentre = false
                }
            }
            .onEnded { value in
                let moved = dragFraction
                let wasSnapped = snappedToCentre
                drag = .zero
                snappedToCentre = false
                guard abs(value.translation.width) + abs(value.translation.height) > 2
                else { return }
                onChange(sticker.reshaped(
                    x: wasSnapped ? 0.5 : sticker.x + moved.x,
                    y: sticker.y + moved.y))
            }
    }

    /// One finger on the bottom-right corner: scale and rotate together.
    private var cornerDrag: some Gesture {
        DragGesture(coordinateSpace: .named(Self.stageSpace))
            .onChanged { value in
                guard let move = CaptionGestureMath.cornerDrag(
                    centre: CGPoint(
                        x: sticker.x * stageSize.width, y: sticker.y * stageSize.height),
                    start: value.startLocation,
                    current: value.location)
                else { return }
                handleScale = move.scale
                handleTwist = move.angleDelta
            }
            .onEnded { _ in
                let grown = sticker.scale * handleScale
                let turned = sticker.angle + handleTwist
                handleScale = 1
                handleTwist = 0
                // `CaptionSticker.init` clamps both.
                onChange(sticker.reshaped(scale: grown, angle: turned))
            }
    }
}

extension CaptionSticker {
    /// This sticker with some fields changed. `init` does the clamping, so a
    /// runaway pinch can't be saved.
    func reshaped(
        x: Double? = nil, y: Double? = nil,
        style: Style? = nil,
        scale: Double? = nil, angle: Double? = nil,
        tint: Tint? = nil
    ) -> CaptionSticker {
        CaptionSticker(
            x: x ?? self.x,
            y: y ?? self.y,
            style: style ?? self.style,
            scale: scale ?? self.scale,
            angle: angle ?? self.angle,
            tint: tint ?? self.tint)
    }
}
