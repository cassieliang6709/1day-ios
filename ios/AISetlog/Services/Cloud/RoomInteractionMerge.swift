import Foundation

/// How a room poll folds remote reactions and comments into what this
/// phone already has, and whether that result is actually new.
///
/// A visible room syncs every ten seconds. Writing the same arrays back
/// into `@Observable` stores made the page redraw — and used to make a
/// comment that had just been typed vanish until the next fetch included
/// it. The rules live here so they can be checked without CloudKit.
enum RoomInteractionMerge {
    /// How long a reaction or comment I just added on a friend's take is
    /// kept on screen while the room's answer doesn't have it yet: the
    /// save may still be in flight, or saved but not yet in query results.
    static let myGrace: TimeInterval = 120

    /// The fetched interactions plus my own recent ones the fetch didn't
    /// return. Replacing them outright made a comment I had just typed
    /// vanish on the next poll and flicker back later — or never, if it
    /// failed.
    static func keepingMine(
        fetched: (
            reactions: [CloudKitService.RemoteReaction],
            comments: [CloudKitService.RemoteComment]
        ),
        existing: (
            reactions: [CloudKitService.RemoteReaction],
            comments: [CloudKitService.RemoteComment]
        ),
        myID: String?,
        now: Date,
        grace: TimeInterval = myGrace
    ) -> (
        reactions: [CloudKitService.RemoteReaction],
        comments: [CloudKitService.RemoteComment]
    ) {
        guard let myID else { return fetched }
        let recent = { (date: Date) in now.timeIntervalSince(date) < grace }
        var reactions = fetched.reactions
        for mine in existing.reactions
        where mine.authorID == myID && recent(mine.createdAt)
            && !reactions.contains(where: {
                $0.authorID == myID && $0.emoji == mine.emoji && $0.day == mine.day
                    && $0.targetAuthorID == mine.targetAuthorID
            })
        {
            reactions.append(mine)
        }
        var comments = fetched.comments
        let ids = Set(comments.map(\.id))
        for mine in existing.comments
        where mine.authorID == myID && recent(mine.createdAt) && !ids.contains(mine.id) {
            comments.append(mine)
        }
        return (reactions, comments)
    }

    /// Reactions that belong on one of my cards, plus any of mine the
    /// remote list has not caught up with.
    static func reactions(
        remote: [CloudKitService.RemoteReaction],
        existing: [ClipReaction],
        day: Int,
        myID: String?
    ) -> [ClipReaction] {
        var reactions = remote
            .filter { $0.day == day && $0.targetAuthorID == myID }
            .map {
                ClipReaction(
                    emoji: $0.emoji, authorID: $0.authorID,
                    authorName: $0.authorName, createdAt: $0.createdAt)
            }
        for mine in existing where mine.authorID == myID {
            if !reactions.contains(where: { $0.id == mine.id }) { reactions.append(mine) }
        }
        return reactions
    }

    /// Comments that belong on one of my cards, plus any of mine the
    /// remote list has not caught up with, in the order they were written.
    static func comments(
        remote: [CloudKitService.RemoteComment],
        existing: [ClipComment],
        day: Int,
        myID: String?
    ) -> [ClipComment] {
        var comments = remote
            .filter { $0.day == day && $0.targetAuthorID == myID }
            .compactMap { rc -> ClipComment? in
                guard let uuid = UUID(uuidString: rc.id) else { return nil }
                return ClipComment(
                    id: uuid, text: rc.text, authorID: rc.authorID,
                    authorName: rc.authorName, createdAt: rc.createdAt)
            }
        for mine in existing where mine.authorID == myID {
            if !comments.contains(where: { $0.id == mine.id }) { comments.append(mine) }
        }
        return comments.sorted { $0.createdAt < $1.createdAt }
    }

    /// Same interactions, ignoring fetch order: a poll can hand back the
    /// same rows in a different sequence, which is not a reason to redraw.
    static func isUnchanged(
        _ current: [CloudKitService.RemoteReaction]?,
        _ incoming: [CloudKitService.RemoteReaction]
    ) -> Bool {
        (current ?? []).sorted(by: RemoteReactionOrder.isOrderedBefore)
            == incoming.sorted(by: RemoteReactionOrder.isOrderedBefore)
    }

    static func isUnchanged(
        _ current: [CloudKitService.RemoteComment]?,
        _ incoming: [CloudKitService.RemoteComment]
    ) -> Bool {
        (current ?? []).sorted(by: RemoteCommentOrder.isOrderedBefore)
            == incoming.sorted(by: RemoteCommentOrder.isOrderedBefore)
    }
}

private enum RemoteReactionOrder {
    static func isOrderedBefore(
        _ lhs: CloudKitService.RemoteReaction,
        _ rhs: CloudKitService.RemoteReaction
    ) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        if lhs.targetAuthorID != rhs.targetAuthorID { return lhs.targetAuthorID < rhs.targetAuthorID }
        if lhs.authorID != rhs.authorID { return lhs.authorID < rhs.authorID }
        if lhs.emoji != rhs.emoji { return lhs.emoji < rhs.emoji }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.authorName < rhs.authorName
    }
}

private enum RemoteCommentOrder {
    static func isOrderedBefore(
        _ lhs: CloudKitService.RemoteComment,
        _ rhs: CloudKitService.RemoteComment
    ) -> Bool {
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.text < rhs.text
    }
}
