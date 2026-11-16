import XCTest
@testable import AISetlog

final class ClipFilingTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: 10))!
    }

    private func story(
        startDay: Int,
        orientation: Challenge.Orientation = .portrait,
        filled: Int = 0,
        total: Int = 3
    ) -> Challenge {
        Challenge(
            id: UUID(),
            title: "story",
            startDate: date(startDay),
            cards: (1...total).map {
                DayCard(day: $0, clipFileName: $0 <= filled ? "clip\($0).mov" : nil)
            },
            mode: .oneDay,
            orientation: orientation)
    }


    func testOnlyStoriesShotTheSameWayRoundCanTakeAClip() {
        let portrait = story(startDay: 1, orientation: .portrait)
        let landscape = story(startDay: 1, orientation: .landscape)

        let forLandscape = ClipFiling.candidates(
            in: [portrait, landscape], orientation: .landscape)

        XCTAssertEqual(forLandscape.map(\.id), [landscape.id])
    }

    func testSquareStoriesAndSquareClipsOnlyMatchEachOther() {
        let portrait = story(startDay: 1, orientation: .portrait)
        let landscape = story(startDay: 1, orientation: .landscape)
        let square = story(startDay: 1, orientation: .square)
        let all = [portrait, landscape, square]

        XCTAssertEqual(
            ClipFiling.candidates(in: all, orientation: .square).map(\.id), [square.id])
        XCTAssertEqual(
            ClipFiling.candidates(in: all, orientation: .portrait).map(\.id), [portrait.id])
    }

    func testLegacyStoriesWithNoOrientationCountAsPortrait() {
        var legacy = story(startDay: 1)
        legacy.orientation = nil

        XCTAssertEqual(
            ClipFiling.candidates(in: [legacy], orientation: .portrait).count, 1)
        XCTAssertTrue(
            ClipFiling.candidates(in: [legacy], orientation: .landscape).isEmpty)
    }

    func testNoStoriesMeansNowhereToFile() {
        XCTAssertTrue(ClipFiling.candidates(in: [], orientation: .portrait).isEmpty)
    }

    func testAFullStoryIsNotSomewhereToFile() {
        let full = story(startDay: 1, filled: 3, total: 3)
        let room = story(startDay: 1, filled: 2, total: 3)

        XCTAssertEqual(
            ClipFiling.candidates(in: [full, room], orientation: .portrait).map(\.id),
            [room.id])
    }

    func testAStoryWithOneSlotLeftIsStillACandidate() {
        let nearlyFull = story(startDay: 1, filled: 2, total: 3)

        XCTAssertEqual(
            ClipFiling.candidates(in: [nearlyFull], orientation: .portrait).count, 1)
    }


    func testNoStoryAtAllInThatFrameSaysSo() {
        let landscape = story(startDay: 1, orientation: .landscape)

        XCTAssertEqual(
            ClipFiling.blocker(in: [landscape], orientation: .portrait),
            .noStoryWithThisFrame)
    }

    func testMatchingStoriesThatAreAllFullSayThatInstead() {
        let full = story(startDay: 1, filled: 3, total: 3)
        let alsoFull = story(startDay: 2, filled: 3, total: 3)

        XCTAssertEqual(
            ClipFiling.blocker(in: [full, alsoFull], orientation: .portrait),
            .everyMatchingStoryIsFull)
    }

    func testAMatchingStoryWithNoSlotsCountsAsFullNotAsMissing() {
        var empty = story(startDay: 1, total: 1)
        empty.cards = []

        XCTAssertEqual(
            ClipFiling.blocker(in: [empty], orientation: .portrait),
            .everyMatchingStoryIsFull)
    }

    func testLegacyStoriesCountAsPortraitWhenExplainingTheBlock() {
        var legacy = story(startDay: 1, filled: 3, total: 3)
        legacy.orientation = nil

        XCTAssertEqual(
            ClipFiling.blocker(in: [legacy], orientation: .portrait),
            .everyMatchingStoryIsFull)
        XCTAssertEqual(
            ClipFiling.blocker(in: [legacy], orientation: .landscape),
            .noStoryWithThisFrame)
    }

    func testNoStoriesAtAllIsAMissingFrameNotAFullOne() {
        XCTAssertEqual(
            ClipFiling.blocker(in: [], orientation: .portrait),
            .noStoryWithThisFrame)
    }

    func testAFilableClipHasNoBlocker() {
        let room = story(startDay: 1, filled: 2, total: 3)

        XCTAssertNil(ClipFiling.blocker(in: [room], orientation: .portrait))
    }

    func testOneStoryWithRoomBeatsAnyNumberOfFullOnes() {
        let full = story(startDay: 1, filled: 3, total: 3)
        let room = story(startDay: 2, filled: 1, total: 3)

        XCTAssertNil(ClipFiling.blocker(in: [full, room], orientation: .portrait))
    }


    func testClipLandsInTheFirstEmptySlot() {
        let partly = story(startDay: 1, filled: 2, total: 3)

        XCTAssertEqual(ClipFiling.targetDay(in: partly), 3)
    }

    func testAGapIsFilledBeforeTheEnd() {
        var gapped = story(startDay: 1, filled: 3, total: 3)
        gapped.cards[1].clipFileName = nil

        XCTAssertEqual(ClipFiling.targetDay(in: gapped), 2)
    }

    func testAFullStoryHasNowhereToPutIt() {
        let full = story(startDay: 1, filled: 3, total: 3)

        XCTAssertNil(ClipFiling.targetDay(in: full))
    }

    func testAStoryWithNoSlotsHasNowhereToPutItEither() {
        var empty = story(startDay: 1, total: 1)
        empty.cards = []

        XCTAssertNil(ClipFiling.targetDay(in: empty))
        XCTAssertTrue(ClipFiling.candidates(in: [empty], orientation: .portrait).isEmpty)
    }
}
