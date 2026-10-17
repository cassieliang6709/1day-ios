import Foundation

/// Every clip the app knows about, in one list: yours and your friends', from
/// every story and room, plus the drafts nobody filed. This is what 我的 shows
/// (1.5) — the archive, with stories as one way of filtering it rather than
/// the only way in.
///
/// Pure value type so the filtering and the calendar grouping can be tested
/// without a store.
struct LibraryClip: Identifiable, Hashable {
    enum Source: Hashable {
        case story(id: UUID, title: String, isShared: Bool)
        case draft(id: UUID)
    }

    let id: String
    let url: URL
    let recordedAt: Date
    let authorName: String?
    let isMine: Bool
    let source: Source
    let orientation: Challenge.Orientation
    /// The clip as the stitcher wants it.
    let clip: DayClip

    static func == (lhs: LibraryClip, rhs: LibraryClip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var storyID: UUID? {
        if case .story(let id, _, _) = source { return id }
        return nil
    }

    /// What `ClipCameraIndex` files this clip's camera under. The file, plus
    /// its date, so a re-recorded take at the same path is read again.
    var cameraKey: String { ClipCameraIndex.key(url: url, recordedAt: recordedAt) }
}

/// The archive's filters: the chip row (待归档, or one camera) and whose
/// clips (the people menu). `.all` is none of them.
struct LibraryFilter: Hashable {
    enum People: Hashable, CaseIterable { case everyone, mine, friends }

    /// Nil = every camera.
    var camera: CameraStyle?
    var people: People = .everyone
    /// 待归档: only the drafts nobody has filed into a story yet.
    var draftsOnly = false

    static let drafts = LibraryFilter(draftsOnly: true)

    static let all = LibraryFilter()
    static let mine = LibraryFilter(people: .mine)
    static let friends = LibraryFilter(people: .friends)
    static func camera(_ style: CameraStyle) -> LibraryFilter { LibraryFilter(camera: style) }
}

struct ClipLibrary {
    let clips: [LibraryClip]

    /// Newest first. Clips without a recorded date sort by the story's start,
    /// which is the best date the app has for them.
    init(clips: [LibraryClip]) {
        self.clips = clips.sorted { $0.recordedAt > $1.recordedAt }
    }

    /// - Parameters:
    ///   - storyClips: what `ChallengeStore.recordedClips(for:)` returns, per story.
    ///   - myIDs: every author ID that means "me" — the account's, and the
    ///     solo placeholder used before sign-in.
    init(
        stories: [(challenge: Challenge, clips: [DayClip])],
        drafts: [(draft: ClipDraft, url: URL)],
        myIDs: Set<String>
    ) {
        var all: [LibraryClip] = []
        for (challenge, clips) in stories {
            for clip in clips {
                all.append(LibraryClip(
                    id: "\(challenge.id.uuidString)/\(clip.id)/\(clip.authorID ?? "")",
                    url: clip.url,
                    recordedAt: clip.recordedAt ?? challenge.startDate,
                    authorName: clip.authorName,
                    isMine: clip.authorID.map(myIDs.contains) ?? true,
                    source: .story(
                        id: challenge.id, title: challenge.title,
                        isShared: challenge.isShared),
                    orientation: challenge.resolvedOrientation,
                    clip: clip))
            }
        }
        for (draft, url) in drafts {
            all.append(LibraryClip(
                id: "draft/\(draft.id.uuidString)",
                url: url,
                recordedAt: draft.recordedAt,
                authorName: nil,
                isMine: true,
                source: .draft(id: draft.id),
                orientation: draft.orientation,
                clip: DayClip(
                    day: 1, url: url, overlayText: draft.overlayText,
                    recordedAt: draft.recordedAt, key: draft.id.uuidString)))
        }
        self.init(clips: all)
    }

    /// - Parameter cameras: each clip's camera, keyed by `cameraKey`. A clip
    ///   not in it yet (its metadata hasn't been read) matches no camera.
    func filtered(
        _ filter: LibraryFilter, cameras: [String: CameraStyle] = [:],
        on day: Date? = nil, calendar: Calendar = .current
    ) -> [LibraryClip] {
        clips.filter { clip in
            let person: Bool = switch filter.people {
            case .everyone: true
            case .mine: clip.isMine
            case .friends: !clip.isMine
            }
            guard person else { return false }
            if filter.draftsOnly, clip.storyID != nil { return false }
            if let camera = filter.camera, cameras[clip.cameraKey] != camera { return false }
            guard let day else { return true }
            return calendar.isDate(clip.recordedAt, inSameDayAs: day)
        }
    }

    /// How many clips the 待归档 chip counts.
    var draftCount: Int { clips.filter { $0.storyID == nil }.count }

    /// The cameras worth a chip: the selectable ones at least one clip was
    /// filmed with, in the picker's order. `.standard` (no camera) never gets
    /// one — those clips live under 全部.
    func cameras(in cameras: [String: CameraStyle]) -> [CameraStyle] {
        let used = Set(clips.compactMap { cameras[$0.cameraKey] })
        return CameraStyle.selectable.filter(used.contains)
    }

    /// The first clip filmed on each day that has any — what a calendar cell
    /// shows as its picture. Keyed by start of day.
    func coverByDay(_ clips: [LibraryClip], calendar: Calendar = .current) -> [Date: LibraryClip] {
        var covers: [Date: LibraryClip] = [:]
        for clip in clips {
            let day = calendar.startOfDay(for: clip.recordedAt)
            if let existing = covers[day], existing.recordedAt <= clip.recordedAt { continue }
            covers[day] = clip
        }
        return covers
    }

    /// The film shape most of `clips` were shot in; portrait on a tie, since
    /// that is the camera's default.
    static func dominantAspect(of clips: [LibraryClip]) -> VideoStitcher.Aspect {
        let counts = Dictionary(grouping: clips, by: \.orientation).mapValues(\.count)
        let best = counts.max { a, b in
            a.value != b.value ? a.value < b.value : a.key != .portrait
        }?.key ?? .portrait
        return switch best {
        case .portrait: .portrait
        case .landscape: .landscape
        case .square: .square
        }
    }

    /// Clips from different stories share `day` numbers; the stitcher's
    /// captions and grouping read them. Renumber in the order given — the
    /// order they were picked in, then dragged into — so every clip is its own
    /// moment and the film plays them in that order.
    static func stitchable(_ clips: [LibraryClip]) -> [DayClip] {
        clips
            .enumerated()
            .map { index, item in
                let c = item.clip
                return DayClip(
                    day: index + 1, url: c.url, authorName: c.authorName,
                    authorID: c.authorID, label: nil, overlayText: c.overlayText,
                    captionSticker: c.captionSticker, recordedAt: c.recordedAt,
                    key: item.id)
            }
    }
}
