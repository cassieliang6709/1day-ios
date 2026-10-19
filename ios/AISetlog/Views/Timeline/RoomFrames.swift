import SwiftUI

/// A shared room as one big frame per person, stacked top to bottom (1.5).
///
/// Each frame is one person's clips, newest first, one clip per page —
/// swipe sideways to go through them. Two people get two frames that split
/// the height between them; more people get shorter frames, and once a
/// frame would drop below `minimumFrameHeight` the stack scrolls instead.
///
/// The face and name at the top of a frame open that person's page
/// (`RoomPersonPage`), every clip of theirs as a grid. Somebody who hasn't
/// filmed gets the 拍一拍 poke where their clips would be; my own empty frame
/// is a way into the camera.
///
/// Who goes in which frame, and in what order, is `RoomFeed.columns` — the
/// same rule the column layout used, so the order didn't change with the
/// shape.
struct RoomFrames: View {
    let clips: [DayClip]
    /// Everyone in the room, as `ChallengeStore.members(for:)` lists them.
    var members: [(id: String, name: String)] = []
    let myID: String
    /// The slot to film next, or nil when every moment holds footage.
    let nextToFilm: Int?
    /// The moment's name, when the story has named moments.
    var slotTitle: (Int) -> String? = { _ in nil }
    /// The clip that was tapped. What opens is the caller's business.
    let onPlay: (DayClip) -> Void
    let onFilm: (Int) -> Void
    /// The face or name at the top of a frame was tapped.
    let onOpenPerson: (RoomFeed.Column) -> Void
    var hasPoked: (String) -> Bool = { _ in false }
    var onPoke: (String) -> Void = { _ in }

    /// Below this a frame is too short to tell what is in the clip, and the
    /// stack scrolls instead. Low enough that three people fit on one phone
    /// screen; four or more scroll.
    private static let minimumFrameHeight: CGFloat = 150
    private static let spacing: CGFloat = 12

    private var columns: [RoomFeed.Column] {
        RoomFeed.columns(clips: clips, members: members, myID: myID)
    }

    var body: some View {
        let columns = columns
        GeometryReader { proxy in
            let count = CGFloat(max(columns.count, 1))
            let fit = (proxy.size.height - Self.spacing * (count - 1)) / count
            let height = max(fit, Self.minimumFrameHeight)
            ScrollView(.vertical) {
                VStack(spacing: Self.spacing) {
                    ForEach(columns) { column in
                        PersonFrame(
                            column: column,
                            nextToFilm: nextToFilm,
                            slotTitle: slotTitle,
                            onPlay: onPlay,
                            onFilm: onFilm,
                            onOpenPerson: { onOpenPerson(column) },
                            hasPoked: hasPoked,
                            onPoke: onPoke)
                            .frame(height: height)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // Everyone fits: nothing to scroll, and a stray drag shouldn't
            // rubber-band the frames.
            .scrollDisabled(fit >= Self.minimumFrameHeight)
        }
    }
}

/// One person's frame: their clips as sideways pages, their face on top.
private struct PersonFrame: View {
    let column: RoomFeed.Column
    let nextToFilm: Int?
    let slotTitle: (Int) -> String?
    let onPlay: (DayClip) -> Void
    let onFilm: (Int) -> Void
    let onOpenPerson: () -> Void
    let hasPoked: (String) -> Bool
    let onPoke: (String) -> Void

    /// The clip on screen. Only that one plays; the others are stills, so a
    /// room with thirty clips isn't thirty players decoding at once.
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-frame")
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
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let at = clip.recordedAt, !Calendar.current.isDateInToday(at) {
                            Text(at.formatted(.dateTime.month().day()
                                .locale(AppLanguage.effective.locale)))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .opacity(0.85)
                        }
                        if let at = clip.recordedAt {
                            Text(at.formatted(.roomClock))
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                        }
                        if let title {
                            Text(title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .padding(14)
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

    /// Face and name, one button: both open this person's page.
    private var person: some View {
        let onVideo = !column.clips.isEmpty
        return Button(action: onOpenPerson) {
            HStack(spacing: 7) {
                AvatarDot(name: column.isMine ? nil : column.name, size: 30, isYou: column.isMine)
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

    /// Which page of how many, and on my own frame a way to film another.
    @ViewBuilder
    private var topTrailing: some View {
        HStack(spacing: 8) {
            if column.clips.count > 1 {
                let index = column.clips.firstIndex { isOnScreen($0) } ?? 0
                Text("\(index + 1) / \(column.clips.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.35), in: Capsule())
            }
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

    /// Nothing filmed yet. Mine is a way into the camera; somebody else's
    /// gets the poke.
    @ViewBuilder
    private var empty: some View {
        if column.isMine {
            Button {
                if let nextToFilm { onFilm(nextToFilm) }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24, weight: .bold))
                    Text(nextToFilm == nil ? Strings.roomColumnEmpty : Strings.roomFeedFilm)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(nextToFilm == nil ? OneDay.inkFaint : OneDay.brandText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(nextToFilm == nil)
            .accessibilityIdentifier("room-feed-film")
        } else {
            let sent = pokedNow || hasPoked(column.id)
            VStack(spacing: 12) {
                Text(Strings.roomColumnEmpty)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                Button {
                    onPoke(column.id)
                    pokedNow = true
                } label: {
                    Label(sent ? Strings.roomTilePoked : Strings.roomTilePoke,
                          systemImage: sent ? "checkmark" : "hand.tap.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(
                            sent ? OneDay.surface : Color.oneDayBrand.opacity(0.14),
                            in: Capsule())
                        .foregroundStyle(sent ? OneDay.inkFaint : OneDay.brandText)
                }
                .buttonStyle(.plain)
                .disabled(sent)
                .accessibilityIdentifier("room-tile-poke")
            }
        }
    }
}

/// One person's clips in a room, all of them, newest first, as a two-wide
/// grid. Reached from the face or name on their frame.
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
                        AvatarDot(name: column.isMine ? nil : column.name, size: 44,
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

                    if column.clips.isEmpty {
                        Text(Strings.roomColumnEmpty)
                            .font(.system(size: 14.5, weight: .medium, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
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
