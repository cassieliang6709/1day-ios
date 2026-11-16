import Foundation

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
    let clip: DayClip

    static func == (lhs: LibraryClip, rhs: LibraryClip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var storyID: UUID? {
        if case .story(let id, _, _) = source { return id }
        return nil
    }

    var cameraKey: String { ClipCameraIndex.key(url: url, recordedAt: recordedAt) }
}

struct LibraryFilter: Hashable {
    enum People: Hashable, CaseIterable { case everyone, mine, friends }

    var camera: CameraStyle?
    var people: People = .everyone
    var draftsOnly = false

    static let drafts = LibraryFilter(draftsOnly: true)

    static let all = LibraryFilter()
    static let mine = LibraryFilter(people: .mine)
    static let friends = LibraryFilter(people: .friends)
    static func camera(_ style: CameraStyle) -> LibraryFilter { LibraryFilter(camera: style) }
}

struct ClipLibrary {
    let clips: [LibraryClip]

    init(clips: [LibraryClip]) {
        self.clips = clips.sorted { $0.recordedAt > $1.recordedAt }
    }

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
                    day: 1, url: url, captions: draft.captions,
                    recordedAt: draft.recordedAt, key: draft.id.uuidString)))
        }
        self.init(clips: all)
    }

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

    func scoped(includingFriends: Bool) -> ClipLibrary {
        guard !includingFriends else { return self }
        var seen: Set<Date> = []
        return ClipLibrary(clips: clips.filter { clip in
            guard clip.isMine else { return false }
            guard clip.storyID != nil, let at = clip.clip.recordedAt else { return true }
            return seen.insert(at).inserted
        })
    }

    var draftCount: Int { clips.filter { $0.storyID == nil }.count }

    func coverByDay(_ clips: [LibraryClip], calendar: Calendar = .current) -> [Date: LibraryClip] {
        var covers: [Date: LibraryClip] = [:]
        for clip in clips {
            let day = calendar.startOfDay(for: clip.recordedAt)
            if let existing = covers[day], existing.recordedAt <= clip.recordedAt { continue }
            covers[day] = clip
        }
        return covers
    }

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

    static func stitchable(_ clips: [LibraryClip]) -> [DayClip] {
        clips
            .enumerated()
            .map { index, item in
                let c = item.clip
                return DayClip(
                    day: index + 1, url: c.url, authorName: c.authorName,
                    authorID: c.authorID, label: nil, captions: c.captions,
                    recordedAt: c.recordedAt,
                    key: item.id)
            }
    }
}
