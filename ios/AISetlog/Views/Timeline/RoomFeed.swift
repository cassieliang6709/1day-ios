import SwiftUI

/// Not on screen for now: the room page draws `RoomFrames` (one big frame per
/// person, stacked) instead. Kept, not deleted — the column layout may come
/// back, and `RoomFeed.columns` is still the rule `RoomFrames` orders people by.
///
/// A shared room as one column per person (1.5) — me first, then everyone
/// else — each column holding *all* of that person's clips, newest at the top.
///
/// The first 1.5 cut was one tile per person showing only their newest take
/// (after Setlog). It answered "who filmed today" and hid everything else: a
/// friend's three clips from this afternoon showed as one, and the only way to
/// see the other two was to open the moment they happened to share with
/// somebody. A column per person keeps the "who" at a glance — face, name and
/// a count at the top of each — and lets the room's footage read as what it
/// is, a few people's days side by side.
///
/// What a tile says is when it was filmed, in large type, and the moment's
/// name only when the room has named moments. Never a day number: a room
/// doesn't count days on screen any more (see `ChallengePresenter.momentName`).
///
/// Two people get two equal columns. Three or more scroll sideways at a fixed
/// width — squeezing four columns into 375pt would make every thumbnail a
/// stamp. Somebody who hasn't filmed anything gets the 拍一拍 poke at the top of
/// their column, where the clips would be.
///
/// Replaces `MomentTimeline` for shared rooms only; a solo story keeps its
/// list of named moments. Tapping a tile opens that moment with everyone's
/// takes in it, as the timeline did.
struct RoomFeed: View {
    let challenge: Challenge
    let clips: [DayClip]
    /// Everyone in the room, as `ChallengeStore.members(for:)` lists them.
    var members: [(id: String, name: String)] = []
    let myID: String
    /// The slot to film next, or nil when every moment holds footage.
    let nextToFilm: Int?
    /// The moment's name, when the story has named moments — nil otherwise,
    /// and then the tile says the time alone.
    var slotTitle: (Int) -> String? = { _ in nil }
    /// Whether I've put a heart on this clip.
    var isLiked: (DayClip) -> Bool = { _ in false }
    /// The tapped take — that person's, that one — not just its moment.
    let onPlay: (DayClip) -> Void
    let onFilm: (Int) -> Void
    var onLike: (DayClip) -> Void = { _ in }
    var onReply: (DayClip) -> Void = { _ in }
    /// 拍一拍 for a friend who hasn't filmed, keyed by their member id.
    /// `hasPoked` answers whether today's poke to them is already spent.
    var hasPoked: (String) -> Bool = { _ in false }
    var onPoke: (String) -> Void = { _ in }

    /// Pokes sent while this feed is on screen; the limiter itself lives in
    /// UserDefaults, which SwiftUI doesn't observe.
    @State private var pokedNow: Set<String> = []

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// One person's column.
    struct Column: Identifiable {
        let id: String
        let name: String
        let isMine: Bool
        /// Every clip of theirs in the room, newest first.
        let clips: [DayClip]
    }

    private func isMine(_ clip: DayClip) -> Bool {
        clip.authorID == myID || clip.authorID == RoomProgress.soloAuthorID
    }

    /// Me first, always — a room is read from your own footage outward. Then
    /// the members in name order, the order the roster used, so a column
    /// doesn't jump sideways every time somebody films. Anyone who filmed but
    /// isn't in `members` yet still gets a column — their footage is the
    /// proof they're here.
    ///
    /// Internal rather than private so `RoomFeedTests` can pin the order and
    /// the grouping without a view hierarchy.
    static func columns(
        clips: [DayClip],
        members: [(id: String, name: String)],
        myID: String
    ) -> [Column] {
        func key(_ clip: DayClip) -> String {
            if clip.authorID == myID || clip.authorID == RoomProgress.soloAuthorID { return myID }
            return clip.authorID ?? clip.authorName ?? clip.id
        }
        let byAuthor = Dictionary(grouping: clips, by: key).mapValues { group in
            group.sorted { ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }
        }

        var seen: Set<String> = [myID]
        var out = [Column(id: myID, name: Strings.youLabel, isMine: true, clips: byAuthor[myID] ?? [])]

        let others = members
            .filter { $0.id != myID && $0.id != RoomProgress.soloAuthorID }
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        for member in others where seen.insert(member.id).inserted {
            out.append(Column(id: member.id, name: member.name, isMine: false,
                              clips: byAuthor[member.id] ?? []))
        }
        // Strangers last, newest footage first among them, so the order is
        // stable for a given set of clips rather than dictionary order.
        let strangers = byAuthor
            .filter { !seen.contains($0.key) }
            .sorted {
                ($0.value.first?.recordedAt ?? .distantPast, $0.key)
                    > ($1.value.first?.recordedAt ?? .distantPast, $1.key)
            }
        for (authorKey, theirs) in strangers {
            out.append(Column(id: authorKey, name: theirs.first?.authorName ?? "",
                              isMine: false, clips: theirs))
        }
        return out
    }

    /// The same month calendar 我的 uses, over this room's clips only.
    /// Picking a day narrows every column to that day's takes.
    @State private var showsCalendar = false
    @State private var day: Date?
    @State private var month = Calendar.current.startOfMonth(for: .now)

    /// The room's clips as library entries, so the calendar dates a clip the
    /// same way 我的 does.
    private var library: ClipLibrary {
        ClipLibrary(stories: [(challenge, clips)], drafts: [], myIDs: [myID])
    }

    /// The clips on screen: all of them, or the picked day's.
    private var shownClips: [DayClip] {
        guard let day else { return clips }
        return library.filtered(.all, on: day).map(\.clip)
    }

    /// Fixed width for a room of three or more, which scrolls sideways. Wide
    /// enough that the time in large type and a two-word moment name still
    /// fit on one line each, narrow enough that the third column peeks in at
    /// the edge of a 375pt phone and says there's more.
    private static let scrollingColumnWidth: CGFloat = 158

    var body: some View {
        VStack(spacing: 0) {
            if let nextToFilm {
                Button { onFilm(nextToFilm) } label: {
                    Label(Strings.roomFeedFilm, systemImage: "camera.fill")
                }
                .buttonStyle(.primaryAction)
                .padding(.bottom, 22)
                .accessibilityIdentifier("room-feed-film")
            }

            if clips.isEmpty && members.count <= 1 {
                Text(Strings.roomFeedEmpty)
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                if !clips.isEmpty { calendarControls }
                waterfall(Self.columns(clips: shownClips, members: members, myID: myID))
            }
        }
    }

    @ViewBuilder
    private func waterfall(_ columns: [Column]) -> some View {
        if columns.count <= 2 {
            HStack(alignment: .top, spacing: 10) {
                ForEach(columns) { column in
                    columnView(column)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                // A room of one keeps half the width rather than blowing my
                // clips up to the whole screen; the empty half is where the
                // friend I invite will go.
                if columns.count == 1 {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(columns) { column in
                        columnView(column)
                            .frame(width: Self.scrollingColumnWidth, alignment: .top)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // The page's 20pt margin would otherwise cut a scrolled column off
            // mid-tile; let it run to the screen edge like a carousel.
            .scrollClipDisabled()
        }
    }

    private func columnView(_ column: Column) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader(column)

            if column.clips.isEmpty {
                // Not while a calendar day is picked: having nothing on one
                // past day isn't a reason to nudge anybody today.
                if !column.isMine, day == nil { pokeButton(column) }
                emptyTile(column)
            }

            ForEach(Array(column.clips.enumerated()), id: \.element.id) { index, clip in
                tile(clip, in: column, isNewest: index == 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-column")
    }

    /// Face, name, and how many clips they have in the room.
    private func columnHeader(_ column: Column) -> some View {
        HStack(spacing: 6) {
            MemberFace(id: column.id, name: column.isMine ? nil : column.name, size: 26, isYou: column.isMine)
            Text(column.name)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Strings.roomColumnClipCount(column.clips.count))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OneDay.inkFaint)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    /// The tile's shape. Portrait, a little shorter than the 9:16 take: a
    /// column of full 9:16 tiles is two clips per screen, and these are for
    /// recognising a clip, not watching it.
    private static let tileAspect: CGFloat = 3 / 4

    /// One clip. The newest in each column plays muted, as the per-person
    /// tile did; the rest are stills, so a room with thirty clips isn't
    /// thirty players decoding at once.
    private func tile(_ clip: DayClip, in column: Column, isNewest: Bool) -> some View {
        let title = slotTitle(clip.day)
        return Button { onPlay(clip) } label: {
            Color.clear
                .aspectRatio(Self.tileAspect, contentMode: .fit)
                .overlay {
                    if isNewest {
                        LoopingClipPlayer(url: clip.url, refreshToken: clip.recordedAt, muted: true)
                    } else {
                        ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt)
                    }
                }
                .overlay {
                    LinearGradient(
                        colors: [.clear, .clear, .black.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let at = clip.recordedAt, !Calendar.current.isDateInToday(at) {
                            // Only off today: a time alone is ambiguous once
                            // the room spans more than one day.
                            Text(at.formatted(.dateTime.month().day()
                                .locale(AppLanguage.effective.locale)))
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
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
                    .padding(10)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        // On the play button itself: a `.contain` container's label isn't
        // read by VoiceOver or matched by UI tests, so the moment's name has
        // to live on the element that is actually tapped.
        .accessibilityLabel(tileLabel(clip, in: column, title: title))
        .accessibilityIdentifier("room-clip-tile")
        // Outside the play button, so a tap on a heart doesn't also open the clip.
        .overlay(alignment: .topTrailing) {
            if !column.isMine { reactions(clip) }
        }
    }

    private func reactions(_ clip: DayClip) -> some View {
        VStack(spacing: 2) {
            Button { onLike(clip) } label: {
                Image(systemName: isLiked(clip) ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isLiked(clip) ? Color.red : .white)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Strings.roomTileLike)
            .accessibilityAddTraits(isLiked(clip) ? .isSelected : [])
            Button { onReply(clip) } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Strings.roomTileReply)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        .padding(2)
    }

    private func tileLabel(_ clip: DayClip, in column: Column, title: String?) -> String {
        [title, column.name,
         clip.recordedAt?.formatted(date: .abbreviated, time: .shortened),
         clip.overlayText]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// Where a column's clips would be, before there are any. Mine is a way
    /// into the camera; somebody else's just says they haven't filmed.
    private func emptyTile(_ column: Column) -> some View {
        let canFilm = column.isMine && nextToFilm != nil
        return Button {
            if canFilm, let nextToFilm { onFilm(nextToFilm) }
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(OneDay.surfaceSoft)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(OneDay.hairline, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
                .aspectRatio(Self.tileAspect, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        if canFilm {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20, weight: .bold))
                        }
                        Text(canFilm ? Strings.roomFeedFilm : Strings.roomColumnEmpty)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(canFilm ? OneDay.brandText : OneDay.inkFaint)
                }
        }
        .buttonStyle(.plain)
        .disabled(!canFilm)
        .accessibilityElement(children: .combine)
    }

    private func pokeButton(_ column: Column) -> some View {
        let sent = pokedNow.contains(column.id) || hasPoked(column.id)
        return Button {
            onPoke(column.id)
            pokedNow.insert(column.id)
        } label: {
            Label(sent ? Strings.roomTilePoked : Strings.roomTilePoke,
                  systemImage: sent ? "checkmark" : "hand.tap.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    sent ? OneDay.surfaceSoft : Color.oneDayBrand.opacity(0.14),
                    in: Capsule())
                .foregroundStyle(sent ? OneDay.inkFaint : OneDay.brandText)
        }
        .buttonStyle(.plain)
        .disabled(sent)
        .accessibilityIdentifier("room-tile-poke")
    }

    @ViewBuilder
    private var calendarControls: some View {
        HStack {
            if let day {
                Button { self.day = nil } label: {
                    Label(
                        "\(day.formatted(.dateTime.month().day())) · \(Strings.libraryAllDays)",
                        systemImage: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.brandText)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 6)
            Button {
                withAnimation(OneDay.Motion.snap) {
                    showsCalendar.toggle()
                    if !showsCalendar { day = nil }
                }
            } label: {
                Image(systemName: showsCalendar ? "rectangle.split.2x1" : "calendar")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(OneDay.ink)
                    .frame(width: 38, height: 38)
                    .background(OneDay.surface, in: Circle())
                    .overlay(Circle().strokeBorder(OneDay.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsCalendar ? Strings.libraryGrid : Strings.libraryCalendar)
            .accessibilityIdentifier("room-feed-calendar")
        }
        .padding(.bottom, 12)

        if showsCalendar {
            LibraryCalendar(
                month: $month,
                covers: library.coverByDay(library.clips),
                selectedDay: $day)
                .padding(.bottom, 14)
        }
    }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// When a room clip was filmed, as a 24-hour clock: 02:07. Both halves
    /// spelled `.twoDigits` — with only the hour padded, 2:07 came out "02:7".
    static var roomClock: Date.FormatStyle {
        .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    }
}
