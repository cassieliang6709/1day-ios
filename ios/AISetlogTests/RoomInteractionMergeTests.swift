import XCTest
@testable import AISetlog

/// How a room poll folds remote reactions and comments into what this
/// phone already has — and whether that result is actually new, so a
/// 10-second sync of an unchanged room does not write `@Observable` state.
final class RoomInteractionMergeTests: XCTestCase {
    private let me = "me-1"
    private let friend = "friend-1"
    private let now = Date(timeIntervalSince1970: 1_000)
    private let grace = RoomInteractionMerge.myGrace

    // MARK: - Keeping mine across a poll that has not caught up

    func testKeepsACommentIJustTypedUntilTheFetchIncludesIt() {
        let mine = comment(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                           text: "刚写的", author: me, at: now.addingTimeInterval(-5))
        let kept = RoomInteractionMerge.keepingMine(
            fetched: (reactions: [], comments: []),
            existing: (reactions: [], comments: [mine]),
            myID: me, now: now)
        XCTAssertEqual(kept.comments, [mine])
    }

    func testDoesNotDuplicateMyCommentOnceTheFetchHasIt() {
        let mine = comment(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                           text: "刚写的", author: me, at: now.addingTimeInterval(-5))
        let kept = RoomInteractionMerge.keepingMine(
            fetched: (reactions: [], comments: [mine]),
            existing: (reactions: [], comments: [mine]),
            myID: me, now: now)
        XCTAssertEqual(kept.comments, [mine])
    }

    func testDropsMyCommentAfterTheGraceIfTheFetchStillLacksIt() {
        let stale = comment(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                            text: "早就发了", author: me,
                            at: now.addingTimeInterval(-(grace + 1)))
        let kept = RoomInteractionMerge.keepingMine(
            fetched: (reactions: [], comments: []),
            existing: (reactions: [], comments: [stale]),
            myID: me, now: now)
        XCTAssertEqual(kept.comments, [])
    }

    func testKeepsMyRecentReactionByEmojiDayAndTargetWithoutDuplicating() {
        let mine = reaction(emoji: "🔥", author: me, target: friend, day: 2, at: now.addingTimeInterval(-8))
        let keptMissing = RoomInteractionMerge.keepingMine(
            fetched: (reactions: [], comments: []),
            existing: (reactions: [mine], comments: []),
            myID: me, now: now)
        XCTAssertEqual(keptMissing.reactions, [mine])

        let keptPresent = RoomInteractionMerge.keepingMine(
            fetched: (reactions: [mine], comments: []),
            existing: (reactions: [mine], comments: []),
            myID: me, now: now)
        XCTAssertEqual(keptPresent.reactions, [mine])
    }

    func testDoesNotKeepSomeoneElsesMissingRecentComment() {
        let theirs = comment(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
                             text: "朋友的", author: friend, at: now.addingTimeInterval(-2))
        let kept = RoomInteractionMerge.keepingMine(
            fetched: (reactions: [], comments: []),
            existing: (reactions: [], comments: [theirs]),
            myID: me, now: now)
        XCTAssertEqual(kept.comments, [])
    }

    // MARK: - Unchanged polls

    func testSameReactionsInADifferentOrderAreUnchanged() {
        let a = reaction(emoji: "🔥", author: friend, target: me, day: 1, at: now)
        let b = reaction(emoji: "✨", author: friend, target: me, day: 2, at: now)
        XCTAssertTrue(RoomInteractionMerge.isUnchanged([a, b], [b, a]))
        XCTAssertTrue(RoomInteractionMerge.isUnchanged([a, b], [a, b]))
    }

    func testSameCommentsInADifferentOrderAreUnchanged() {
        let a = comment(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", text: "a", author: friend, at: now)
        let b = comment(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", text: "b", author: friend, at: now.addingTimeInterval(1))
        XCTAssertTrue(RoomInteractionMerge.isUnchanged([a, b], [b, a]))
    }

    func testNilAndEmptyAreTheSameAndANewRowIsNot() {
        // Readers already treat a missing key as `[]`, so writing an empty
        // list over nil would be a change with nothing user-visible in it.
        XCTAssertTrue(RoomInteractionMerge.isUnchanged(nil as [CloudKitService.RemoteReaction]?, []))
        XCTAssertTrue(RoomInteractionMerge.isUnchanged(nil as [CloudKitService.RemoteComment]?, []))
        XCTAssertTrue(RoomInteractionMerge.isUnchanged([] as [CloudKitService.RemoteReaction], []))
        let row = reaction(emoji: "🔥", author: friend, target: me, day: 1, at: now)
        XCTAssertFalse(RoomInteractionMerge.isUnchanged(nil, [row]))
    }

    func testANewCommentOrARenamedAuthorIsAChange() {
        let before = comment(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                             text: "hi", author: friend, name: "Leo", at: now)
        let added = comment(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
                            text: "new", author: friend, at: now)
        let renamed = comment(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                              text: "hi", author: friend, name: "Leo Chen", at: now)
        XCTAssertFalse(RoomInteractionMerge.isUnchanged([before], [before, added]))
        XCTAssertFalse(RoomInteractionMerge.isUnchanged([before], [renamed]))
    }

    // MARK: - Card merge

    func testCardPicksUpAFriendsReactionOnMyTakeAndIgnoresOtherTargets() {
        let onMine = reaction(emoji: "🩵", author: friend, target: me, day: 1, at: now)
        let onTheirs = reaction(emoji: "🔥", author: friend, target: friend, day: 1, at: now)
        let merged = RoomInteractionMerge.reactions(
            remote: [onMine, onTheirs], existing: [], day: 1, myID: me)
        XCTAssertEqual(merged, [
            ClipReaction(emoji: "🩵", authorID: friend, authorName: "Friend", createdAt: now),
        ])
    }

    func testCardKeepsMyLocalReactionTheFetchHasNotCaught() {
        let mine = ClipReaction(emoji: "🫶", authorID: me, authorName: "Me", createdAt: now)
        let merged = RoomInteractionMerge.reactions(
            remote: [], existing: [mine], day: 1, myID: me)
        XCTAssertEqual(merged, [mine])
        XCTAssertEqual(
            RoomInteractionMerge.reactions(remote: [], existing: merged, day: 1, myID: me),
            merged)
    }

    func testCardCommentsSortByTimeKeepMineAndIgnoreInvalidIds() {
        let earlier = comment(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            text: "先", author: friend, at: now.addingTimeInterval(-10))
        let later = comment(
            id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            text: "后", author: friend, at: now)
        let mine = ClipComment(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            text: "我也说", authorID: me, authorName: "Me", createdAt: now.addingTimeInterval(-5))
        let merged = RoomInteractionMerge.comments(
            remote: [later, earlier, comment(id: "not-a-uuid", text: "丢", author: friend, at: now)],
            existing: [mine],
            day: 1, myID: me)
        XCTAssertEqual(merged.map(\.text), ["先", "我也说", "后"])
        XCTAssertEqual(
            RoomInteractionMerge.comments(
                remote: [later, earlier], existing: merged, day: 1, myID: me),
            merged)
    }

    func testSignedOutMergeStillAppliesRemoteRowsTargetedAtNil() {
        // `targetAuthorID == myID` is false when I am signed out (`myID` is
        // nil), so the card is not rewritten with someone else's thread.
        let remote = [reaction(emoji: "🔥", author: friend, target: friend, day: 1, at: now)]
        XCTAssertEqual(
            RoomInteractionMerge.reactions(remote: remote, existing: [], day: 1, myID: nil),
            [])
    }

    // MARK: - Fixtures

    private func reaction(
        emoji: String, author: String, target: String, day: Int, at: Date
    ) -> CloudKitService.RemoteReaction {
        .init(
            day: day, emoji: emoji, authorID: author,
            authorName: author == me ? "Me" : "Friend",
            targetAuthorID: target, createdAt: at)
    }

    private func comment(
        id: String, text: String, author: String, name: String? = nil, at: Date
    ) -> CloudKitService.RemoteComment {
        .init(
            id: id, day: 1, text: text, authorID: author,
            authorName: name ?? (author == me ? "Me" : "Friend"),
            targetAuthorID: me, createdAt: at)
    }
}
