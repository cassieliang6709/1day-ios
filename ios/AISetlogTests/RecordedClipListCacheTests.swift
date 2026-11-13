import XCTest
@testable import AISetlog

final class RecordedClipListCacheTests: XCTestCase {

    private let id = UUID()
    private let otherID = UUID()

    // MARK: - Hits

    func testSecondCallWithSameInputDoesNotRecompute() {
        let cache = RecordedClipListCache()
        let input = self.input()
        let first = makeClip(day: 1)
        var produced: [DayClip] = []

        let a = cache.clips(for: id, input: input) {
            produced.append(first)
            return [first]
        }
        let b = cache.clips(for: id, input: input) {
            XCTFail("same input should not recompute")
            return [makeClip(day: 99)]
        }

        XCTAssertEqual(cache.computeCount, 1)
        XCTAssertEqual(a, [first])
        XCTAssertEqual(b, [first])
        XCTAssertEqual(produced, [first])
    }

    func testDifferentStoriesAreCachedIndependently() {
        let cache = RecordedClipListCache()
        let one = makeClip(day: 1)
        let two = makeClip(day: 2)

        XCTAssertEqual(
            cache.clips(for: id, input: input()) { [one] },
            [one]
        )
        XCTAssertEqual(
            cache.clips(for: otherID, input: input()) { [two] },
            [two]
        )
        XCTAssertEqual(cache.computeCount, 2)
        XCTAssertEqual(
            cache.clips(for: id, input: input()) {
                XCTFail("story one should still be cached")
                return []
            },
            [one]
        )
    }

    // MARK: - Invalidation

    func testNewOrDeletedOrReplacedClipMissesCache() {
        let cache = RecordedClipListCache()
        var card = DayCard(day: 1, clipFileName: "day1.mov", recordedAt: Date(timeIntervalSince1970: 1))
        _ = cache.clips(for: id, input: input(cards: [card])) { [makeClip(day: 1)] }

        // Deleted.
        XCTAssertEqual(
            cache.clips(for: id, input: input(cards: [DayCard(day: 1)])) { [makeClip(day: 9)] }.first?.day,
            9
        )

        // Replaced file / recordedAt.
        card.clipFileName = "day1-retake.mov"
        card.recordedAt = Date(timeIntervalSince1970: 2)
        XCTAssertEqual(
            cache.clips(for: id, input: input(cards: [card])) { [makeClip(day: 7)] }.first?.day,
            7
        )

        // New take on the same moment.
        card.moreTakes = [
            ClipTake(id: UUID(), fileName: "take2.mov", recordedAt: Date(timeIntervalSince1970: 3), captions: [])
        ]
        XCTAssertEqual(
            cache.clips(for: id, input: input(cards: [card])) { [makeClip(day: 3)] }.first?.day,
            3
        )
        XCTAssertEqual(cache.computeCount, 4)
    }

    func testCaptionReactionCommentOrTitleChangeMissesCache() {
        let cache = RecordedClipListCache()
        var card = DayCard(day: 1, clipFileName: "day1.mov", recordedAt: Date(timeIntervalSince1970: 1))
        _ = cache.clips(for: id, input: input(cards: [card], momentTitles: ["Morning"])) { [makeClip(day: 1)] }

        card.overlayText = "hello"
        XCTAssertEqual(cache.clips(for: id, input: input(cards: [card], momentTitles: ["Morning"])) { [makeClip(day: 2)] }.first?.day, 2)

        card.reactions = [ClipReaction(emoji: "💛", authorID: "me", authorName: "Me")]
        XCTAssertEqual(cache.clips(for: id, input: input(cards: [card], momentTitles: ["Morning"])) { [makeClip(day: 3)] }.first?.day, 3)

        card.comments = [ClipComment(text: "nice", authorID: "me", authorName: "Me", createdAt: Date(timeIntervalSince1970: 4))]
        XCTAssertEqual(cache.clips(for: id, input: input(cards: [card], momentTitles: ["Morning"])) { [makeClip(day: 4)] }.first?.day, 4)

        XCTAssertEqual(cache.clips(for: id, input: input(cards: [card], momentTitles: ["Evening"])) { [makeClip(day: 5)] }.first?.day, 5)
        XCTAssertEqual(cache.computeCount, 5)
    }

    func testRemoteCacheAndAccountAndLanguageMissCache() {
        let cache = RecordedClipListCache()
        let local = input()
        _ = cache.clips(for: id, input: local) { [makeClip(day: 1)] }

        let remoteClip = CloudKitService.RemoteClip(
            id: "r1", day: 1, authorID: "friend", authorName: "Friend",
            recordedAt: Date(timeIntervalSince1970: 8),
            localURL: URL(fileURLWithPath: "/tmp/friend.mov"),
            overlayText: nil
        )
        XCTAssertEqual(
            cache.clips(for: id, input: input(remoteClips: [remoteClip])) { [makeClip(day: 2)] }.first?.day,
            2
        )

        let reaction = CloudKitService.RemoteReaction(
            day: 1, emoji: "🔥", authorID: "friend", authorName: "Friend",
            targetAuthorID: "me", createdAt: Date(timeIntervalSince1970: 9)
        )
        XCTAssertEqual(
            cache.clips(for: id, input: input(remoteClips: [remoteClip], remoteReactions: [reaction])) { [makeClip(day: 3)] }.first?.day,
            3
        )

        let comment = CloudKitService.RemoteComment(
            id: UUID().uuidString, day: 1, text: "wow", authorID: "friend",
            authorName: "Friend", targetAuthorID: "me", createdAt: Date(timeIntervalSince1970: 10)
        )
        XCTAssertEqual(
            cache.clips(for: id, input: input(remoteClips: [remoteClip], remoteReactions: [reaction], remoteComments: [comment])) { [makeClip(day: 4)] }.first?.day,
            4
        )

        XCTAssertEqual(
            cache.clips(for: id, input: input(remoteClips: [remoteClip], remoteReactions: [reaction], remoteComments: [comment], accountID: "me", displayName: "Me")) { [makeClip(day: 5)] }.first?.day,
            5
        )
        XCTAssertEqual(
            cache.clips(for: id, input: input(remoteClips: [remoteClip], remoteReactions: [reaction], remoteComments: [comment], accountID: "me", displayName: "New name")) { [makeClip(day: 6)] }.first?.day,
            6
        )
        XCTAssertEqual(
            cache.clips(for: id, input: input(remoteClips: [remoteClip], remoteReactions: [reaction], remoteComments: [comment], accountID: "me", displayName: "New name", localeCode: "zh-Hans")) { [makeClip(day: 7)] }.first?.day,
            7
        )
        XCTAssertEqual(cache.computeCount, 7)
    }

    func testEmptyAndNilRemoteClipsShareAKey() {
        let cache = RecordedClipListCache()
        let first = makeClip(day: 1)
        XCTAssertEqual(cache.clips(for: id, input: input(remoteClips: nil)) { [first] }, [first])
        XCTAssertEqual(
            cache.clips(for: id, input: input(remoteClips: [])) {
                XCTFail("empty remotes should match nil remotes")
                return []
            },
            [first]
        )
        XCTAssertEqual(cache.computeCount, 1)
    }

    func testKeepOnlyDropsDeletedStories() {
        let cache = RecordedClipListCache()
        let one = makeClip(day: 1)
        _ = cache.clips(for: id, input: input()) { [one] }
        cache.keepOnly(ids: [otherID])
        XCTAssertEqual(
            cache.clips(for: id, input: input()) { [makeClip(day: 8)] }.first?.day,
            8
        )
        XCTAssertEqual(cache.computeCount, 2)
    }

    func testRemoveDropsOneStory() {
        let cache = RecordedClipListCache()
        _ = cache.clips(for: id, input: input()) { [makeClip(day: 1)] }
        cache.remove(id)
        XCTAssertEqual(
            cache.clips(for: id, input: input()) { [makeClip(day: 2)] }.first?.day,
            2
        )
        XCTAssertEqual(cache.computeCount, 2)
    }

    // MARK: - Fixtures

    private func input(
        cards: [DayCard] = [DayCard(day: 1, clipFileName: "day1.mov", recordedAt: Date(timeIntervalSince1970: 1))],
        momentTitles: [String]? = ["Morning"],
        remoteClips: [CloudKitService.RemoteClip]? = nil,
        remoteReactions: [CloudKitService.RemoteReaction] = [],
        remoteComments: [CloudKitService.RemoteComment] = [],
        accountID: String? = nil,
        displayName: String? = nil,
        localeCode: String = "en"
    ) -> RecordedClipListCache.Input {
        RecordedClipListCache.Input(
            challenge: Challenge(
                id: id,
                title: "Week",
                startDate: Date(timeIntervalSince1970: 0),
                cards: cards,
                momentTitles: momentTitles
            ),
            remoteClips: remoteClips,
            remoteReactions: remoteReactions,
            remoteComments: remoteComments,
            accountID: accountID,
            displayName: displayName,
            localeCode: localeCode
        )
    }

    private func makeClip(day: Int) -> DayClip {
        DayClip(
            day: day,
            url: URL(fileURLWithPath: "/tmp/day\(day).mov"),
            recordedAt: Date(timeIntervalSince1970: TimeInterval(day))
        )
    }
}
