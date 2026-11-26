import SwiftUI

struct PersonFrame: View {
    let column: RoomFeed.Column
    let nextToFilm: Int?
    let slotTitle: (Int) -> String?
    let onPlay: (DayClip) -> Void
    let onFilm: (Int) -> Void
    let onOpenPerson: () -> Void
    let hasPoked: (String) -> Bool
    let onPoke: (String) -> Void
    let latestComment: (DayClip) -> ClipComment?
    let myID: String
    let reactions: (DayClip) -> [ClipReaction]
    let onReact: (DayClip, String) -> Void
    let signedOut: Bool
    let onSignIn: () -> Void
    let isLocked: (DayClip) -> Bool
    let onUnlock: () -> Void

    @State private var page: String?
    @State private var pokedNow = false
    @State private var heartOn: String?

    private static let radius: CGFloat = 22

    var body: some View {
        ZStack {
            if column.clips.isEmpty {
                empty
            } else {
                pages
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneDay.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(alignment: .bottom) { pageDots }
        .contextMenu {
            if let clip = onScreenClip, !column.isMine, !isLocked(clip) {
                Picker(Strings.reactLabel, selection: Binding(
                    get: { myReaction(clip) ?? "" },
                    set: { if !$0.isEmpty { onReact(clip, $0) } })) {
                    ForEach(ClipReaction.palette, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.palette)
            }
            pokeMenu
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-frame")
    }

    @ViewBuilder
    private var pokeMenu: some View {
        if !column.isMine {
            let sent = pokedNow || hasPoked(column.id)
            Button {
                onPoke(column.id)
                pokedNow = true
            } label: {
                Label(sent ? Strings.roomTilePoked : Strings.roomTilePoke,
                      systemImage: sent ? "checkmark" : "hand.tap.fill")
            }
            .disabled(sent)
            .accessibilityIdentifier("room-tile-poke")
        }
    }

    private var pages: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(column.clips) { clip in
                    clipPage(clip)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
    }

    private var onScreenClip: DayClip? {
        column.clips.first { isOnScreen($0) }
    }

    private func myReaction(_ clip: DayClip) -> String? {
        reactions(clip).filter { $0.authorID == myID }.max { $0.createdAt < $1.createdAt }?.emoji
    }

    private func doubleTap(_ clip: DayClip) {
        let heart = ClipReaction.palette[0]
        if !reactions(clip).contains(where: { $0.authorID == myID && $0.emoji == heart }) {
            onReact(clip, heart)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heartOn = clip.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(OneDay.Motion.soft) { if heartOn == clip.id { heartOn = nil } }
        }
    }

    private func isOnScreen(_ clip: DayClip) -> Bool {
        (page ?? column.clips.first?.id) == clip.id
    }

    @ViewBuilder
    private func clipPage(_ clip: DayClip) -> some View {
        if isLocked(clip) {
            RoomLockedFace(
                clip: clip,
                meta: [column.name, clip.recordedAt?.formatted(.roomClock)]
                    .compactMap { $0 }.joined(separator: " · "),
                onUnlock: onUnlock)
        } else {
            unlockedPage(clip)
        }
    }

    @ViewBuilder
    private func unlockedPage(_ clip: DayClip) -> some View {
        let title = slotTitle(clip.day)
        let face = clipFace(clip, title: title)
            .overlay {
                if heartOn == clip.id {
                    Text(ClipReaction.palette[0])
                        .font(OneDay.Font.rounded(.largeTitle))
                        .scaleEffect(2.4)
                        .shadow(color: .black.opacity(0.25), radius: 8)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                [title, column.name,
                 clip.recordedAt?.formatted(date: .abbreviated, time: .shortened),
                 clip.overlayText]
                    .compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier("room-clip-tile")
        if column.isMine {
            face
                .onTapGesture { onPlay(clip) }
                .accessibilityAction { onPlay(clip) }
        } else {
            face
                .onTapGesture(count: 2) { doubleTap(clip) }
                .onTapGesture { onPlay(clip) }
                .accessibilityAction { onPlay(clip) }
                .accessibilityAction(named: Text(Strings.reactLabel)) { doubleTap(clip) }
        }
    }

    private func clipFace(_ clip: DayClip, title: String?) -> some View {
            Color.clear
                .overlay {
                    ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt, bedsInsteadOfCrops: true)
                    if isOnScreen(clip) {
                        LoopingClipPlayer(url: clip.url, refreshToken: clip.recordedAt, muted: true, fits: true)
                    }
                }
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: OneDay.Space.xs) {
                    if let comment = latestComment(clip) {
                        HStack(spacing: 6) {
                            MemberFace(id: comment.authorID, name: comment.authorName, size: 22, showsMood: false)
                            Text(comment.text)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(OneDay.ink)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.9), in: Capsule())
                        }
                        .frame(maxWidth: 260, alignment: .leading)
                    }
                        Text(Self.metaLine(clip, name: column.name, title: title))
                            .font(OneDay.Font.caption)
                            .lineLimit(1)
                    }
                    .padding(OneDay.Space.m)
                }
                .overlay(alignment: .topTrailing) { reactionBadges(clip) }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .contentShape(Rectangle())
    }

    static func shownReactions(_ reactions: [ClipReaction]) -> [ClipReaction] {
        Array(reactions.sorted { $0.createdAt > $1.createdAt }.prefix(4))
    }

    @ViewBuilder
    private func reactionBadges(_ clip: DayClip) -> some View {
        let shown = Self.shownReactions(reactions(clip))
        if !shown.isEmpty {
            HStack(spacing: OneDay.Space.xs) {
                ForEach(shown) { reaction in
                    let isMe = reaction.authorID == myID
                    ReactionGlyph(key: reaction.emoji, size: 18)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.28), in: Circle())
                        .overlay(alignment: .bottomTrailing) {
                            MemberFace(id: reaction.authorID, name: isMe ? nil : reaction.authorName,
                                       size: 16, isYou: isMe, showsMood: false)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                                .offset(x: OneDay.Space.xs, y: OneDay.Space.xs)
                        }
                }
            }
            .padding(OneDay.Space.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shown.map { reaction in
                let who = reaction.authorID == myID ? Strings.youLabel : reaction.authorName
                return "\(who) \(reaction.emoji)"
            }.joined(separator: ", "))
            .accessibilityIdentifier("room-clip-reactions")
        }
    }

    static func metaLine(_ clip: DayClip, name: String, title: String?) -> String {
        var parts: [String] = [name]
        if let at = clip.recordedAt {
            parts.append(Calendar.current.isDateInToday(at)
                ? at.formatted(.roomClock)
                : at.formatted(.dateTime.month().day().locale(AppLanguage.effective.locale))
                    + " " + at.formatted(.roomClock))
        }
        if let caption = clip.overlayText ?? title, !caption.isEmpty { parts.append(caption) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var pageDots: some View {
        if column.clips.count > 1 {
            HStack(spacing: 5) {
                ForEach(column.clips.prefix(8)) { clip in
                    Circle()
                        .fill(.white.opacity(isOnScreen(clip) ? 1 : 0.45))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 9)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var empty: some View {
        if column.isMine, let nextToFilm {
            Button { onFilm(nextToFilm) } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(OneDay.brandText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.roomFeedFilm)
            .accessibilityIdentifier("room-feed-film")
        } else if !column.isMine, signedOut {
            VStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(OneDay.inkFaint)
                Button(Strings.signedOutFrame, action: onSignIn)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black, in: Capsule())
                    .accessibilityIdentifier("room-frame-sign-in")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !column.isMine {
            let sent = pokedNow || hasPoked(column.id)
            Button {
                onPoke(column.id)
                pokedNow = true
            } label: {
                Label(sent ? Strings.roomTilePoked : Strings.roomTilePoke,
                      systemImage: sent ? "checkmark" : "hand.tap.fill")
                    .font(OneDay.Font.callout)
                    .foregroundStyle(sent ? OneDay.inkSoft : OneDay.brandText)
                    .padding(.horizontal, OneDay.Space.l)
                    .frame(minHeight: 44)
                    .background(Color.oneDayBrand.opacity(sent ? 0.08 : 0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("room-frame-poke")
        } else {
            Color.clear
        }
    }
}
