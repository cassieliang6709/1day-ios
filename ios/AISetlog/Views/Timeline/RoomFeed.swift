import SwiftUI

/// A shared room as one tile per person (1.5) — modelled on Setlog: each
/// member's newest take plays muted in their tile, with who filmed it, the
/// time in large type and their caption. Somebody who hasn't filmed today is a
/// grey tile that says how long it's been, so the room shows who's missing
/// without a separate list.
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
    /// The moment's name, when the story has named moments. Read out with the
    /// tile, so a moment can still be found by what it's called.
    var slotTitle: (Int) -> String? = { _ in nil }
    /// Whether I've put a heart on this clip.
    var isLiked: (DayClip) -> Bool = { _ in false }
    let onPlay: (Int) -> Void
    let onFilm: (Int) -> Void
    var onLike: (DayClip) -> Void = { _ in }
    var onReply: (DayClip) -> Void = { _ in }
    /// 拍一拍 for a friend's grey tile, keyed by their member id. `hasPoked`
    /// answers whether today's poke to them is already spent.
    var hasPoked: (String) -> Bool = { _ in false }
    var onPoke: (String) -> Void = { _ in }

    /// Pokes sent while this feed is on screen; the limiter itself lives in
    /// UserDefaults, which SwiftUI doesn't observe.
    @State private var pokedNow: Set<String> = []

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private struct Tile: Identifiable {
        let id: String
        let name: String
        let isMine: Bool
        /// Their newest take, today or not.
        let latest: DayClip?
        var filmedToday: Bool {
            guard let at = latest?.recordedAt else { return false }
            return Calendar.current.isDateInToday(at)
        }
    }

    private func isMine(_ clip: DayClip) -> Bool {
        clip.authorID == myID || clip.authorID == RoomProgress.soloAuthorID
    }

    /// One per person: people with a take today first, newest first; then the
    /// ones still to film. Anyone who filmed but isn't in `members` yet still
    /// gets a tile — their footage is the proof they're here.
    private var tiles: [Tile] {
        var newest: [String: DayClip] = [:]
        for clip in clips {
            let key = isMine(clip) ? myID : (clip.authorID ?? clip.authorName ?? clip.id)
            let at = clip.recordedAt ?? .distantPast
            if let held = newest[key], (held.recordedAt ?? .distantPast) >= at { continue }
            newest[key] = clip
        }

        var seen = Set<String>()
        var out: [Tile] = []
        for member in members {
            let mine = member.id == myID
            let key = mine ? myID : member.id
            guard seen.insert(key).inserted else { continue }
            out.append(Tile(id: key, name: mine ? Strings.youLabel : member.name,
                            isMine: mine, latest: newest[key]))
        }
        for (key, clip) in newest where !seen.contains(key) {
            seen.insert(key)
            let mine = key == myID
            out.append(Tile(id: key, name: mine ? Strings.youLabel : (clip.authorName ?? ""),
                            isMine: mine, latest: clip))
        }
        if !seen.contains(myID) {
            out.append(Tile(id: myID, name: Strings.youLabel, isMine: true, latest: nil))
        }

        return out.sorted { a, b in
            if a.filmedToday != b.filmedToday { return a.filmedToday }
            return (a.latest?.recordedAt ?? .distantPast) > (b.latest?.recordedAt ?? .distantPast)
        }
    }

    /// The same month calendar 我的 uses, over this room's clips only.
    /// Picking a day swaps today's tiles for that day's takes.
    @State private var showsCalendar = false
    @State private var day: Date?
    @State private var month = Calendar.current.startOfMonth(for: .now)

    /// The room's clips as library entries, so the calendar dates a clip the
    /// same way 我的 does.
    private var library: ClipLibrary {
        ClipLibrary(stories: [(challenge, clips)], drafts: [], myIDs: [myID])
    }

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

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

                if let day {
                    dayGrid(library.filtered(.all, on: day).map(\.clip))
                } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(tiles) { tile in
                        if tile.filmedToday, let clip = tile.latest {
                            liveTile(tile, clip: clip)
                        } else {
                            greyTile(tile)
                        }
                    }
                }
                }
            }
        }
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
                Image(systemName: showsCalendar ? "square.grid.2x2" : "calendar")
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

    /// Every take from the picked day, oldest first, as a still with who and when.
    private func dayGrid(_ dayClips: [DayClip]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(dayClips.sorted { ($0.recordedAt ?? .distantPast) < ($1.recordedAt ?? .distantPast) }) { clip in
                Button { onPlay(clip.day) } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt) }
                        .overlay {
                            LinearGradient(
                                colors: [.black.opacity(0.35), .clear, .black.opacity(0.35)],
                                startPoint: .top, endPoint: .bottom)
                        }
                        .overlay(alignment: .topLeading) {
                            Text(isMine(clip) ? Strings.youLabel : (clip.authorName ?? ""))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .lineLimit(1)
                                .padding(10)
                        }
                        .overlay(alignment: .bottomLeading) {
                            if let at = clip.recordedAt {
                                Text(at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .padding(10)
                            }
                        }
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func header(_ tile: Tile, dimmed: Bool) -> some View {
        HStack(spacing: 6) {
            AvatarDot(name: tile.isMine ? nil : tile.name, size: 26, isYou: tile.isMine)
            Text(tile.name)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .opacity(dimmed ? 0.55 : 1)
        .padding(10)
    }

    private func liveTile(_ tile: Tile, clip: DayClip) -> some View {
        Button { onPlay(clip.day) } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { LoopingClipPlayer(url: clip.url, refreshToken: clip.recordedAt, muted: true) }
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.35), .clear, .black.opacity(0.35)],
                        startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .topLeading) { header(tile, dimmed: false) }
                .overlay {
                    VStack(spacing: 2) {
                        if let at = clip.recordedAt {
                            Text(at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                        }
                        if let caption = clip.overlayText, !caption.isEmpty {
                            Text(caption)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 10)
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
        .accessibilityLabel(tileLabel(tile, clip: clip))
        // Outside the play button, so a tap on a heart doesn't also open the clip.
        .overlay(alignment: .trailing) {
            if !tile.isMine {
                VStack(spacing: 14) {
                    Button { onReply(clip) } label: {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Strings.roomTileReply)
                    Button { onLike(clip) } label: {
                        Image(systemName: isLiked(clip) ? "heart.fill" : "heart")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isLiked(clip) ? Color.red : .white)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Strings.roomTileLike)
                    .accessibilityAddTraits(isLiked(clip) ? .isSelected : [])
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                .padding(.trailing, 4)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tileLabel(_ tile: Tile, clip: DayClip) -> String {
        [slotTitle(clip.day), tile.name,
         clip.recordedAt?.formatted(date: .omitted, time: .shortened),
         clip.overlayText]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private func greyStatus(_ tile: Tile) -> String {
        guard let at = tile.latest?.recordedAt else { return Strings.roomTileNeverFilmed }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: at),
            to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return days >= 2 ? Strings.roomTileLastFilmed(daysAgo: days) : Strings.roomTileNotToday
    }

    private func greyTile(_ tile: Tile) -> some View {
        let canFilm = tile.isMine && nextToFilm != nil
        return Button {
            if canFilm, let nextToFilm { onFilm(nextToFilm) }
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.16))
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) { header(tile, dimmed: true) }
                .overlay {
                    VStack(spacing: 6) {
                        if canFilm {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20, weight: .bold))
                        }
                        Text(canFilm ? Strings.roomFeedFilm : greyStatus(tile))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!canFilm)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottom) {
            if !tile.isMine { pokeButton(tile) }
        }
    }

    private func pokeButton(_ tile: Tile) -> some View {
        let sent = pokedNow.contains(tile.id) || hasPoked(tile.id)
        return Button {
            onPoke(tile.id)
            pokedNow.insert(tile.id)
        } label: {
            Label(sent ? Strings.roomTilePoked : Strings.roomTilePoke,
                  systemImage: sent ? "checkmark" : "hand.tap.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(.white.opacity(sent ? 0.08 : 0.16), in: Capsule())
                .foregroundStyle(.white.opacity(sent ? 0.45 : 0.9))
        }
        .buttonStyle(.plain)
        .disabled(sent)
        .padding(.bottom, 12)
        .accessibilityIdentifier("room-tile-poke")
    }
}
