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
    /// Live pinch and twist, for the duration of the gesture only — same rule
    /// as `captionDrag`: the card stores the committed value, never a delta.
    @State private var pinch: CGFloat = 1
    @State private var twist: Double = 0
    /// Tapped once: the caption is selected, not being typed into.
    ///
    /// Two taps rather than one because one tap has to keep meaning "let me
    /// see the handles". Dragging, pinching and twisting a caption all worked
    /// before this and nothing on screen said so, so the only people who found
    /// them were the ones who tried by accident.
    @State private var captionSelected = false
    /// A one-finger corner drag, live. Same rule as `pinch` and `twist`: the
    /// card keeps the committed value, these keep the gesture.
    @State private var handleScale: CGFloat = 1
    @State private var handleTwist: Double = 0
    /// Whether the drag is currently held on the frame's middle.
    @State private var snappedToCentre = false
    /// Shown under the caption the first time it is selected, then never again
    /// — the same way every app that has these gestures teaches them.
    @AppStorage("caption.gestureHintSeen.v1") private var gestureHintSeen = false
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
            backdrop
            reviewLayout
            if showLook { lookOverlay }
        }
        .statusBarHidden()
        // The keyboard is allowed to cover the bottom of this screen rather
        // than to resize it. Letting it push made the picture jump to a
        // different size the moment you started typing, and the whole point of
        // placing a caption here is that what you see is what gets exported.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: url) { measuredAspect = await ClipGeometry.aspect(of: url) }
        .sheet(isPresented: $showComments) { commentsSheet }
        .onChange(of: captionFocused) { _, focused in
            if !focused, editingCaption { saveCaption() }
        }
        .onSubmit { captionFocused = false }
    }

    // MARK: - The video, and the one thing drawn where the film draws it

    /// One screen. The picture is big and inset; everything you can do to it is
    /// a row under it.
    ///
    /// This replaces two layouts and the button between them. Edge to edge was
    /// what a tap on a grid tile used to do — no border, no ✕ in the picture —
    /// and the fix for that had been a small card with a list of rows beneath
    /// it plus a 全屏看 button to get the big version back. So the screen had
    /// two sizes, a caption could only be placed accurately in one of them,
    /// and the list read like a settings page: 加字幕, 聊聊这个瞬间 and 重拍
    /// stacked as three identical rows, when one of the three is what you came
    /// to do and another only exists in a room.
    ///
    /// Now: the picture keeps its own shape on its blurred bed, inset with a
    /// rounded edge so there is somewhere for the ✕ to live, and the three
    /// things sit side by side underneath. Captions are written and placed
    /// right here, at the size the film exports at.
    private var reviewLayout: some View {
        VStack(spacing: 10) {
            top
            // Centred in what's left under the title bar, not top-aligned: a
            // 9:8 stitched moment is only about 40% of the height, and pinning
            // it up top left the bottom third of the screen empty.
            Spacer(minLength: 0)
            Color.clear
                // `Color.clear` rather than the player: an aspect-filling
                // player reports the size it filled to, and a ZStack/VStack
                // lays siblings out in the widest child. A 9:8 stitched moment
                // measured 1.125 screens wide that way and pushed 重拍 and
                // 聊天 clean off the display. Clear takes the offered size and
                // an overlay can't feed back into it.
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay { videoStage }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
            Spacer(minLength: 0)
            bottomControls
        }
        // 13pt rather than 16: the picture is the point, and this is the
        // narrowest margin that still leaves the ✕ somewhere to sit.
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Under the picture: who and when, the reactions, the caption's colour and
    /// backing, then the three buttons.
    ///
    /// Hidden while the keyboard is up rather than removed. The keyboard covers
    /// this strip anyway, but taking it out of the layout let the two `Spacer`s
    /// re-centre the picture — so starting to type slid the whole frame down
    /// the screen, which is the one thing this screen must not do while you are
    /// placing a caption on it.
    private var bottomControls: some View {
        VStack(spacing: 9) {
            byline
            // The reaction strip used to be here, between the byline and the
            // buttons. It lives in the moment's chat now — the other place
            // people say something about a take — so this screen is the
            // picture and three things you can do to it.
            if isMine, hasCaption {
                tintRows
                plateRow
            }
            buttonRow
        }
        .opacity(editingCaption ? 0 : 1)
        .allowsHitTesting(!editingCaption)
        .animation(OneDay.Motion.soft, value: editingCaption)
    }

    /// The player plus the caption layer, sized by whoever hosts it.
    private var videoStage: some View {
        ZStack {
            if isLive {
                // Review is the truth: show the captured file without the personal look.
                // The look belongs in the dedicated adjustment/export surface.
                LoopingClipPlayer(url: url, refreshToken: recordedAt, look: .none)
            } else {
                Color.black
            }
            captionLayer
        }
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
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
    }

    /// Twelve colours, two rows of six, all on screen.
    ///
    /// It was six in one row and every one of them was a brand colour, which
    /// made the row read as the app's palette rather than as a choice — and it
    /// had no black, so a caption over snow, a white wall or a blown-out window
    /// had nothing legible to be. Two rows rather than a scroller: a colour you
    /// have to swipe to find is a colour nobody picks.
    private var tintRows: some View {
        VStack(spacing: 7) {
            ForEach(Array(tintPages.enumerated()), id: \.offset) { _, page in
                HStack(spacing: 7) {
                    ForEach(page) { tint in
                        Button {
                            saveSticker(reshaped(
                                style: CaptionSticker.legibleStyle(
                                    picking: tint, keeping: sticker.style),
                                tint: tint))
                        } label: {
                            Circle()
                                .fill(tint.color)
                                .frame(height: 26)
                                .frame(maxWidth: .infinity)
                                .overlay {
                                    // Two rings, outside the dot: white for the
                                    // edge every dot needs against footage, and
                                    // blue outside that for the chosen one. A
                                    // white ring *was* the selection, which is
                                    // invisible on the white dot — the one
                                    // colour most captions start as.
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
                        .accessibilityLabel(tint.rawValue)
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

    /// The four backings, drawn as what they are.
    ///
    /// This replaces a 格式 button that cycled three styles: it could not say
    /// what it was about to pick, so finding the dark band meant tapping until
    /// it appeared. The samples say 字 in the caption's own colour on the
    /// backing they would give it.
    private var plateRow: some View {
        HStack(spacing: 7) {
            ForEach(CaptionSticker.Style.picker) { style in
                let chosen = style == sticker.style.pickerEquivalent
                // What tapping it would actually give you, colour correction
                // included — so the square is a preview and not a label.
                let sample = CaptionSticker(
                    x: 0.5, y: 0.5, style: style,
                    tint: CaptionSticker.legibleTint(
                        picking: style, keeping: sticker.tint))
                Button {
                    saveSticker(reshaped(style: style, tint: sample.tint))
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
                                // "No backing" has to look like no backing, not
                                // like a fourth colour of one: a faint fill and
                                // a dashed edge, so it doesn't read as the
                                // dimmed band sitting next to it.
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
                            // Blue for the same reason as the colour dots: a
                            // white ring around the white sample is not there.
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

    /// The three things you can do to a moment, side by side.
    ///
    /// Not a stacked list: 加字幕 is what almost everybody opened this screen
    /// for, 重拍 is occasional, and 聊天 only exists in a room — three
    /// identical rows said they were the same size of decision.
    private var buttonRow: some View {
        HStack(spacing: 7) {
            if isMine {
                actionButton(
                    hasCaption ? "textformat" : "text.badge.plus",
                    hasCaption ? Strings.captionEditAction : Strings.captionAction,
                    accented: !isShared,
                    identifier: "moment-caption",
                    action: startEditingCaption)
                actionButton(
                    "arrow.counterclockwise", Strings.rerecordShort,
                    accented: false, identifier: "moment-rerecord", action: onReRecord)
            }
            if isShared {
                // Accented here rather than 加字幕: in a room the thing that
                // isn't obvious is that a moment has a thread on it at all.
                actionButton(
                    "bubble.left.fill", Strings.chatShort,
                    accented: true, identifier: "moment-chat",
                    badge: comments.isEmpty ? nil : comments.count
                ) { showComments = true }
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
                    .minimumScaleFactor(0.8)
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accented ? .white.opacity(0.85) : OneDay.inkSoft)
                }
            }
            .foregroundStyle(accented ? .white : OneDay.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if accented {
                    Capsule().fill(OneDay.brandHorizontal)
                } else {
                    Capsule().fill(.white.opacity(0.92))
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
            // Darker than it was: it is the whole background now, not a strip
            // either side of a filling clip, and the inset card needs something
            // to sit against.
            .overlay(Color.black.opacity(editingCaption ? 0.38 : 0.52))
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
                ZStack {
                    // Tapping the picture puts the handles away. Only while
                    // something is selected: the rest of the time this layer
                    // must not eat taps meant for the video underneath it.
                    if captionSelected {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { deselectCaption() }
                        if snappedToCentre { centreGuide }
                    }

                    captionText(text, in: proxy.size)
                        // Inside the flexible frame, so the box is laid out
                        // against the words themselves — including however many
                        // lines they wrapped to — and inside the scale and the
                        // rotation, so it grows and turns with them. Overlaid
                        // outside either one, it stayed the size and the angle
                        // the caption was before the gesture.
                        .overlay {
                            if captionSelected, isMine { selectionChrome(in: proxy.size) }
                        }
                        .frame(maxWidth: proxy.size.width * 0.76)
                        // Live pinch and twist multiply the saved values rather
                        // than replacing them, so a second gesture starts from
                        // where the first one left off.
                        .scaleEffect(pinch * handleScale)
                        .rotationEffect(.degrees(sticker.angle + twist + handleTwist))
                        .contentShape(Rectangle())
                        .onTapGesture { tapCaption() }
                        .position(
                            x: (sticker.x + dragFraction(in: proxy.size).x) * proxy.size.width,
                            y: (sticker.y + dragFraction(in: proxy.size).y) * proxy.size.height)
                        .gesture(isMine ? shapeSticker(in: proxy.size) : nil)
                        .animation(nil, value: captionDrag)
                        .animation(nil, value: pinch)
                        .animation(nil, value: twist)
                        .animation(nil, value: handleScale)
                        .animation(nil, value: handleTwist)

                    if captionSelected, isMine, !gestureHintSeen { gestureHint }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .coordinateSpace(name: Self.stageSpace)
                // The guide appearing is the feedback that the sticker snapped;
                // the tap is felt rather than watched, because at that moment
                // the finger is covering the caption.
                .sensoryFeedback(.alignment, trigger: snappedToCentre) { _, now in now }
            }
        }
    }

    /// The name the corner handle's drag measures itself in. A drag reported in
    /// the handle's own space starts at the same point every time, which is no
    /// use for an angle around the sticker's centre.
    private static let stageSpace = "caption-stage"

    /// The dashed box, the three corners and the ✕ — nothing that moves the
    /// sticker on its own except the bottom-right corner.
    ///
    /// Drawn inside the scale and rotation, so the box hugs the words at
    /// whatever size and angle they are. During a live gesture it grows with
    /// them, which is what makes the corner feel attached to the text.
    private func selectionChrome(in size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(
                .white.opacity(0.92),
                style: StrokeStyle(lineWidth: 1.2, dash: [4.5, 3.5]))
            .padding(-9)
            .overlay(alignment: .topLeading) {
                Button(action: deleteCaption) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(OneDay.ink)
                        .frame(width: 20, height: 20)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: -19, y: -19)
                .accessibilityLabel(Strings.deleteCaptionAction)
                .accessibilityIdentifier("caption-delete")
            }
            .overlay(alignment: .topTrailing) { handleDot.offset(x: 4, y: -14) }
            .overlay(alignment: .bottomLeading) { handleDot.offset(x: -14, y: 4) }
            .overlay(alignment: .bottomTrailing) {
                handleDot
                    .offset(x: 4, y: 4)
                    // The one corner that does something. Bottom-right because
                    // that is where it is in every app that has this, and
                    // because it is the corner a right thumb reaches without
                    // covering the words.
                    .gesture(cornerDrag(in: size))
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

    /// The middle of the frame, drawn only while the sticker is held on it.
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

    /// Drag, pinch and twist at once. Simultaneously rather than exclusively:
    /// a two-finger gesture that starts as a pinch almost always rotates a
    /// little too, and having the first millimetre of movement decide which
    /// one you meant makes both feel broken.
    private func shapeSticker(in size: CGSize) -> some Gesture {
        SimultaneousGesture(
            dragSticker(in: size),
            SimultaneousGesture(
                MagnifyGesture()
                    .onChanged { pinch = $0.magnification }
                    .onEnded { value in
                        pinch = 1
                        saveSticker(reshaped(scale: sticker.scale * value.magnification))
                    },
                RotateGesture()
                    .onChanged { twist = $0.rotation.degrees }
                    .onEnded { value in
                        twist = 0
                        saveSticker(reshaped(angle: sticker.angle + value.rotation.degrees))
                    }))
    }

    /// The current sticker with one field changed. `CaptionSticker.init` does
    /// the clamping, so a runaway pinch can't be saved.
    private func reshaped(
        x: Double? = nil, y: Double? = nil,
        style: CaptionSticker.Style? = nil,
        scale: Double? = nil, angle: Double? = nil,
        tint: CaptionSticker.Tint? = nil
    ) -> CaptionSticker {
        CaptionSticker(
            x: x ?? sticker.x,
            y: y ?? sticker.y,
            style: style ?? sticker.style,
            scale: scale ?? sticker.scale,
            angle: angle ?? sticker.angle,
            tint: tint ?? sticker.tint)
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
            .onChanged { value in
                guard size.width > 0 else {
                    captionDrag = value.translation
                    return
                }
                // Snapping is applied to the *live* translation, not just to
                // what gets saved: a caption that jumps into place only after
                // the finger lifts reads as the app moving it somewhere you
                // didn't put it.
                let wanted = sticker.x + value.translation.width / size.width
                if let snapped = CaptionGestureMath.snapToCentre(wanted) {
                    captionDrag = CGSize(
                        width: (snapped - sticker.x) * size.width,
                        height: value.translation.height)
                    snappedToCentre = true
                } else {
                    captionDrag = value.translation
                    snappedToCentre = false
                }
            }
            .onEnded { value in
                let moved = dragFraction(in: size)
                let wasSnapped = snappedToCentre
                captionDrag = .zero
                snappedToCentre = false
                guard abs(value.translation.width) + abs(value.translation.height) > 2
                else { return }
                saveSticker(reshaped(
                    x: wasSnapped ? 0.5 : sticker.x + moved.x,
                    y: sticker.y + moved.y))
            }
    }

    /// One finger on the bottom-right corner: scale and rotate together.
    private func cornerDrag(in size: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.stageSpace))
            .onChanged { value in
                guard let move = CaptionGestureMath.cornerDrag(
                    centre: CGPoint(
                        x: sticker.x * size.width, y: sticker.y * size.height),
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
                // `CaptionSticker.init` clamps both, so a corner dragged across
                // the screen cannot save a caption too big to fit or turned far
                // enough to read as a mistake.
                saveSticker(reshaped(scale: grown, angle: turned))
            }
    }

    /// First tap selects, second tap types. A caption nobody has selected is
    /// not editable by accident, which is the other half of the fix: the whole
    /// video used to be a button into the text editor.
    private func tapCaption() {
        guard isMine else { return }
        if captionSelected {
            // Selected means the hint has been on screen, so this counts as
            // taught whichever way the selection ends.
            gestureHintSeen = true
            startEditingCaption()
        } else {
            withAnimation(OneDay.Motion.soft) { captionSelected = true }
        }
    }

    private func deselectCaption() {
        withAnimation(OneDay.Motion.soft) { captionSelected = false }
        // Counted as taught once it has been on screen through a selection.
        gestureHintSeen = true
    }

    /// The ✕ on the box. Clears the words; the sticker's place, size, angle and
    /// colour stay on the card, so writing a new caption puts it back where
    /// this one was rather than at the default centre.
    private func deleteCaption() {
        guard let challengeID else { return }
        store.updateOverlayText("", day: day, challengeID: challengeID)
        captionDraft = ""
        withAnimation(OneDay.Motion.soft) { captionSelected = false }
        gestureHintSeen = true
    }

    /// Same fractions, weights and shadow the stitcher uses, so what you read
    /// here is what gets exported.
    private func captionText(_ text: String, in size: CGSize) -> some View {
        let minEdge = min(size.width, size.height)
        let base = minEdge * (sticker.style == .headline ? 0.092 : 0.062)
        let fontSize = base * sticker.scale
        return Text(text)
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
                    // The radius is a fraction of the plate's height, which for
                    // a one-line caption is the font size plus both paddings.
                    RoundedRectangle(
                        cornerRadius: fontSize * (1 + plate.padV * 2) * plate.radius,
                        style: .continuous
                    )
                    .fill(fill)
                }
            }
            // Only the two plateless styles need their own edge; words on a bar
            // are already sitting on one.
            .shadow(
                color: .black.opacity(sticker.style.plate == nil ? 0.28 : 0),
                radius: 5, y: 2)
    }

    // MARK: - Chrome

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
                // No `onOpenMoment` here: this screen *is* one moment and has
                // no navigation of its own, so it cannot honour a quote
                // pointing at a different one. The quotes stay plain labels —
                // better than an arrow that does nothing four times out of
                // five. The room chat opened from the story timeline is where
                // they're links.
                RoomChatView(
                    challengeID: challengeID,
                    moment: day,
                    reactionTarget: .init(day: day, authorID: targetAuthorID ?? myID))
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.oneDayMist)
    }

    // MARK: - Caption

    /// Always full screen. A caption is placed as a fraction of the exported
    /// frame, so placing one inside a 16pt-inset card means aiming at a
    /// smaller picture than the one it lands on — and the keyboard would take
    /// most of that card. Staying full screen afterwards is deliberate too:
    /// the first thing you want after writing it is to see it.
    private func startEditingCaption() {
        captionDraft = liveOverlayText ?? ""
        editingCaption = true
        captionFocused = true
        // The handles have no business being on screen behind a keyboard.
        //
        // Deliberately *not* marking the hint as seen: writing the words is
        // how most captions start, and this used to run before anybody had
        // ever selected one — so the line that teaches the gestures was
        // retired by the act of typing, and never appeared at all.
        captionSelected = false
    }

    private func saveCaption() {
        editingCaption = false
        guard let challengeID else { return }
        store.updateOverlayText(captionDraft, day: day, challengeID: challengeID)
    }
}
