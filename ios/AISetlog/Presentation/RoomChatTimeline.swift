import Foundation

/// A clip somebody put in the room, as a line in the chat.
///
/// Nothing about it is sent. The room's clips are already on the phone —
/// `ChallengeStore.recordedClips(for:)` is what the room page draws — so the
/// chat builds these from the same list and slots them between the messages
/// by when each clip was filmed. A new CloudKit record type for "X filmed
/// something" would be a second copy of a fact the room already syncs, and
/// would have to be kept in step with deletes and retakes it knows nothing
/// about.
struct RoomChatClipEvent: Identifiable, Equatable {
    let id: String
    let day: Int
    let url: URL
    let authorName: String
    let isMine: Bool
    let recordedAt: Date
    /// The moment's own name; nil in a room without named moments, and then
    /// the line says only who filmed.
    let momentTitle: String?
}

/// One row of the chat: something somebody said, or something they filmed.
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

    /// Who this row is from, for grouping runs. A clip of mine is keyed by
    /// my chat account id so a clip and a message of mine are one run.
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
    /// The room's clips as chat events. A clip with no `recordedAt` has no
    /// place in a timeline and is left out rather than pinned to the top.
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

    /// Messages and clips in one stream, oldest first. Messages keep the
    /// order the session gave them — that order already settles same-second
    /// sends — and a clip goes in front of any message from the same instant
    /// or later, so "看我拍的" lands under the clip it's about.
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
