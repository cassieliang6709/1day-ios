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
    var signedOut = false
    var onSignIn: () -> Void = {}

    private static let minimumFrameHeight: CGFloat = 150
    private static let spacing: CGFloat = 12

    static func grid(for count: Int) -> (columns: Int, rows: Int) {
        switch count {
        case ...1: return (1, 1)
        case 2: return (2, 1)
        case 3: return (1, 3)
        case 4: return (2, 2)
        default: return (2, (count + 1) / 2)
        }
    }

    private var columns: [RoomFeed.Column] {
        RoomFeed.columns(clips: clips, members: members, myID: myID)
    }

    var body: some View {
        if orientation == .landscape {
            stacked
        } else {
            portraitGrid
        }
    }

    private var stacked: some View {
        let columns = columns
        return GeometryReader { proxy in
            let height = proxy.size.width * 9 / 16
            let total = height * CGFloat(columns.count) + Self.spacing * CGFloat(max(columns.count - 1, 0))
            ScrollView(.vertical) {
                VStack(spacing: Self.spacing) {
                    ForEach(columns) { column in
                        frame(column).frame(height: height)
                    }
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(total <= proxy.size.height)
        }
    }

    private var portraitGrid: some View {
        let columns = columns
        let grid = Self.grid(for: columns.count)
        let rows = stride(from: 0, to: columns.count, by: grid.columns).map {
            Array(columns[$0..<min($0 + grid.columns, columns.count)])
        }
        return GeometryReader { proxy in
            let count = CGFloat(grid.rows)
            let fit = (proxy.size.height - Self.spacing * (count - 1)) / count
            let cellWidth = (proxy.size.width - Self.spacing * CGFloat(grid.columns - 1))
                / CGFloat(grid.columns)
            let height = columns.count == 2
                ? min(cellWidth * 4 / 3, proxy.size.height)
                : max(fit, Self.minimumFrameHeight)
            ScrollView(.vertical) {
                VStack(spacing: Self.spacing) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: Self.spacing) {
                            ForEach(rows[index]) { column in
                                frame(column)
                            }
                            ForEach(0..<(grid.columns - rows[index].count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: height)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(fit >= Self.minimumFrameHeight)
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
        .overlay(alignment: .topLeading) { person }
        .overlay(alignment: .topTrailing) { topTrailing }
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
                    if isOnScreen(clip) {
                        LoopingClipPlayer(url: clip.url, refreshToken: clip.recordedAt, muted: true)
                    } else {
                        ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt)
                    }
                }
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom)
                }
                .overlay {
                    VStack(spacing: 2) {
                        if let at = clip.recordedAt, !Calendar.current.isDateInToday(at) {
                            Text(at.formatted(.dateTime.month().day()
                                .locale(AppLanguage.effective.locale)))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .opacity(0.85)
                        }
                        if let at = clip.recordedAt {
                            Text(at.formatted(.roomClock))
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                        }
                        if let caption = clip.overlayText ?? title, !caption.isEmpty {
                            Text(caption)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .overlay(alignment: .bottomLeading) {
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
                        .padding(10)
                        .frame(maxWidth: 260, alignment: .leading)
                    }
                }
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

    private var person: some View {
        let onVideo = !column.clips.isEmpty
        return Button(action: onOpenPerson) {
            HStack(spacing: 7) {
                MemberFace(id: column.id, name: column.isMine ? nil : column.name, size: 30, isYou: column.isMine)
                    .padding(2)
                    .overlay {
                        Circle().strokeBorder(Color.oneDayBrand, lineWidth: onVideo ? 2 : 0)
                    }
                Text(column.name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(onVideo ? .white : OneDay.ink)
                    .shadow(color: .black.opacity(onVideo ? 0.4 : 0), radius: 3, y: 1)
                    .lineLimit(1)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("room-frame-person")
    }

    @ViewBuilder
    private var topTrailing: some View {
        HStack(spacing: 8) {
            if column.isMine, !column.clips.isEmpty, let nextToFilm {
                Button { onFilm(nextToFilm) } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(OneDay.onBrand)
                        .frame(width: 36, height: 36)
                        .background(Color.oneDayBrand, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.roomFeedFilm)
                .accessibilityIdentifier("room-feed-film")
            }
        }
        .padding(6)
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(column.name)
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundStyle(OneDay.ink)
                                .lineLimit(1)
                            Text(Strings.roomColumnClipCount(column.clips.count))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(OneDay.inkFaint)
                        }
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
