import SwiftUI

struct RoomFrames: View {
    let clips: [DayClip]
    var members: [(id: String, name: String)] = []
    let myID: String
    let nextToFilm: Int?
    var slotTitle: (Int) -> String? = { _ in nil }
    let onPlay: (DayClip) -> Void
    let onFilm: (Int) -> Void
    let onOpenPerson: (RoomFeed.Column) -> Void
    var hasPoked: (String) -> Bool = { _ in false }
    var onPoke: (String) -> Void = { _ in }
    var orientation: Challenge.Orientation = .portrait
    var latestComment: (DayClip) -> ClipComment? = { _ in nil }
    var reactions: (DayClip) -> [ClipReaction] = { _ in [] }
    var onReact: (DayClip, String) -> Void = { _, _ in }
    var signedOut = false
    var onSignIn: () -> Void = {}

    private static let minimumFrameHeight: CGFloat = 150
    private static let spacing: CGFloat = 12

    static func filmedFirst(_ columns: [RoomFeed.Column]) -> [RoomFeed.Column] {
        columns.enumerated().sorted { a, b in
            let rank: (RoomFeed.Column) -> Int = { $0.isMine ? 0 : ($0.clips.isEmpty ? 2 : 1) }
            return rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
        }.map(\.element)
    }

    static func grid(for count: Int, landscape: Bool) -> (columns: Int, rows: Int) {
        if landscape || count <= 1 { return (1, max(count, 1)) }
        return (2, (count + 1) / 2)
    }

    static func cellSize(
        in space: CGSize, count: Int, aspect: CGFloat, landscape: Bool
    ) -> CGSize {
        let grid = grid(for: count, landscape: landscape)
        let columns = CGFloat(grid.columns)
        let rows = CGFloat(grid.rows)
        let byWidth = (space.width - spacing * (columns - 1)) / columns
        let byHeight = (space.height - spacing * (rows - 1)) / rows
        let height = max(min(byWidth / aspect, byHeight), minimumFrameHeight)
        return CGSize(width: min(height * aspect, byWidth), height: height)
    }

    private var columns: [RoomFeed.Column] {
        Self.filmedFirst(RoomFeed.columns(clips: clips, members: members, myID: myID))
            .filter { !$0.clips.isEmpty }
    }

    private var aspect: CGFloat {
        CameraStyle.defaultCamera.aspectRatio(for: orientation) ?? 3 / 4
    }

    var body: some View {
        let columns = columns
        let landscape = orientation == .landscape
        let grid = Self.grid(for: columns.count, landscape: landscape)
        let rows = stride(from: 0, to: columns.count, by: grid.columns).map {
            Array(columns[$0..<min($0 + grid.columns, columns.count)])
        }
        return GeometryReader { proxy in
            let cell = Self.cellSize(
                in: proxy.size, count: columns.count, aspect: aspect, landscape: landscape)
            let total = cell.height * CGFloat(grid.rows) + Self.spacing * CGFloat(grid.rows - 1)
            ScrollView(.vertical) {
                VStack(spacing: Self.spacing) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: Self.spacing) {
                            ForEach(rows[index]) { column in
                                frame(column).frame(width: cell.width, height: cell.height)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(total <= proxy.size.height + 1)
        }
    }

    private func frame(_ column: RoomFeed.Column) -> some View {
        PersonFrame(
            column: column,
            nextToFilm: nextToFilm,
            slotTitle: slotTitle,
            onPlay: onPlay,
            onFilm: onFilm,
            onOpenPerson: { onOpenPerson(column) },
            hasPoked: hasPoked,
            onPoke: onPoke,
            latestComment: latestComment,
            myID: myID,
            reactions: reactions,
            onReact: onReact,
            signedOut: signedOut,
            onSignIn: onSignIn)
    }
}

private struct PersonFrame: View {
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

    @State private var page: String?
    @State private var pokedNow = false

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
        .contextMenu { pokeMenu }
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

    private func isOnScreen(_ clip: DayClip) -> Bool {
        (page ?? column.clips.first?.id) == clip.id
    }

    private func clipPage(_ clip: DayClip) -> some View {
        let title = slotTitle(clip.day)
        return Button { onPlay(clip) } label: {
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
        .buttonStyle(.plain)
        .accessibilityLabel(
            [title, column.name,
             clip.recordedAt?.formatted(date: .abbreviated, time: .shortened),
             clip.overlayText]
                .compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("room-clip-tile")
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

struct RoomPersonPage: View {
    let column: RoomFeed.Column
    var slotTitle: (Int) -> String? = { _ in nil }
    let onPlay: (DayClip) -> Void

    @Environment(\.dismiss) private var dismiss

    private static let tileAspect: CGFloat = 3 / 4

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        MemberFace(id: column.id, name: column.isMine ? nil : column.name, size: 44,
                                   isYou: column.isMine)
                        Text(column.name)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(OneDay.ink)
                            .lineLimit(1)
                    }

                    if !column.clips.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10),
                                      GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(column.clips) { clip in tile(clip) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    IconBubble(systemName: "chevron.left", label: Strings.back) { dismiss() }
                        .accessibilityIdentifier("room-person-back")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: OneDay.tabBarClearance)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func tile(_ clip: DayClip) -> some View {
        let title = slotTitle(clip.day)
        return Button { onPlay(clip) } label: {
            Color.clear
                .aspectRatio(Self.tileAspect, contentMode: .fit)
                .overlay { ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt) }
                .overlay {
                    LinearGradient(
                        colors: [.clear, .clear, .black.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let at = clip.recordedAt, !Calendar.current.isDateInToday(at) {
                            Text(at.formatted(.dateTime.month().day()
                                .locale(AppLanguage.effective.locale)))
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .opacity(0.85)
                        }
                        if let at = clip.recordedAt {
                            Text(at.formatted(.roomClock))
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                        }
                        if let title {
                            Text(title)
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("room-person-clip")
    }
}
