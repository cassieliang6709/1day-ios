import Foundation

struct RoomChatClipEvent: Identifiable, Equatable {
    let id: String
    let day: Int
    let url: URL
    let authorName: String
    let isMine: Bool
    let recordedAt: Date
    let momentTitle: String?
}

enum RoomChatItem: Identifiable, Equatable {
    case message(RoomChatEntry)
    case clip(RoomChatClipEvent)

    var id: String {
        switch self {
        case .message(let entry): "message-\(entry.id.uuidString)"
        case .clip(let event): "clip-\(event.id)"
        }
    }

    var date: Date {
        switch self {
        case .message(let entry): entry.message.createdAt
        case .clip(let event): event.recordedAt
        }
    }

    func authorKey(myID: String) -> String {
        switch self {
        case .message(let entry): entry.message.authorID
        case .clip(let event): event.isMine ? myID : "clip:\(event.authorName)"
        }
    }

    var entry: RoomChatEntry? {
        if case .message(let entry) = self { return entry }
        return nil
    }
}

enum RoomChatTimeline {
    static func clipEvents(
        from clips: [DayClip],
        myID: String,
        momentTitle: (Int) -> String?
    ) -> [RoomChatClipEvent] {
        clips.compactMap { clip in
            guard let at = clip.recordedAt else { return nil }
            let mine = clip.authorID == myID || clip.authorID == RoomProgress.soloAuthorID
            return RoomChatClipEvent(
                id: clip.id,
                day: clip.day,
                url: clip.url,
                authorName: mine ? Strings.youLabel : (clip.authorName ?? ""),
                isMine: mine,
                recordedAt: at,
                momentTitle: momentTitle(clip.day))
        }
    }

    static func merge(entries: [RoomChatEntry], clips: [RoomChatClipEvent]) -> [RoomChatItem] {
        let sortedClips = clips.sorted { ($0.recordedAt, $0.id) < ($1.recordedAt, $1.id) }
        var out: [RoomChatItem] = []
        out.reserveCapacity(entries.count + sortedClips.count)
        var next = 0
        for entry in entries {
            while next < sortedClips.count, sortedClips[next].recordedAt <= entry.message.createdAt {
                out.append(.clip(sortedClips[next]))
                next += 1
            }
            out.append(.message(entry))
        }
        out.append(contentsOf: sortedClips[next...].map(RoomChatItem.clip))
        return out
    }
}
