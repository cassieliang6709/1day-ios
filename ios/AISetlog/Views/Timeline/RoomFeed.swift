import SwiftUI

struct RoomFeed: View {
    let challenge: Challenge
    let clips: [DayClip]
    var members: [(id: String, name: String)] = []
    let myID: String
    let nextToFilm: Int?
    var slotTitle: (Int) -> String? = { _ in nil }
    var isLiked: (DayClip) -> Bool = { _ in false }
    let onPlay: (DayClip) -> Void
    let onFilm: (Int) -> Void
    var onLike: (DayClip) -> Void = { _ in }
    var onReply: (DayClip) -> Void = { _ in }
    var hasPoked: (String) -> Bool = { _ in false }
    var onPoke: (String) -> Void = { _ in }
    var showsCalendarControls = true

    @State private var pokedNow: Set<String> = []

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    struct Column: Identifiable {
        let id: String
        let name: String
        let isMine: Bool
        let clips: [DayClip]
    }

    private func isMine(_ clip: DayClip) -> Bool {
        clip.authorID == myID || clip.authorID == RoomProgress.soloAuthorID
    }

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

    @State private var showsCalendar = false
    @State private var day: Date?
    @State private var month = Calendar.current.startOfMonth(for: .now)

    private var library: ClipLibrary {
        ClipLibrary(stories: [(challenge, clips)], drafts: [], myIDs: [myID])
    }

    private var shownClips: [DayClip] {
        guard let day else { return clips }
        return library.filtered(.all, on: day).map(\.clip)
    }

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
                if !clips.isEmpty, showsCalendarControls { calendarControls }
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
            .scrollClipDisabled()
        }
    }

    private func columnView(_ column: Column) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader(column)

            if column.clips.isEmpty {
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

    private static let tileAspect: CGFloat = 3 / 4

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
        .accessibilityLabel(tileLabel(clip, in: column, title: title))
        .accessibilityIdentifier("room-clip-tile")
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

extension FormatStyle where Self == Date.VerbatimFormatStyle {
    static var roomClock: Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: .current,
            calendar: Calendar(identifier: .gregorian))
    }
}
