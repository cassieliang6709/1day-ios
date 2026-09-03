import XCTest
@testable import AISetlog

/// Where a loose clip is allowed to go. The camera and the drafts list both
/// ask this, and they have to give the same answer — a clip you couldn't file
/// on the day shouldn't become permanently unfilable once it's a draft.
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

    // MARK: - Candidates

    func testOnlyStoriesShotTheSameWayRoundCanTakeAClip() {
        let portrait = story(startDay: 1, orientation: .portrait)
        let landscape = story(startDay: 1, orientation: .landscape)

        let forLandscape = ClipFiling.candidates(
            in: [portrait, landscape], orientation: .landscape)

        XCTAssertEqual(forLandscape.map(\.id), [landscape.id])
    }

    /// Stories saved before the orientation field existed decode as nil and
    /// are all portrait; they must still show up for a portrait clip.
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

    /// The data-loss bug, as a candidate list. A full story used to be offered,
    /// and filing into it overwrote whatever was on the day the story was on.
    func testAFullStoryIsNotSomewhereToFile() {
        let full = story(startDay: 1, filled: 3, total: 3)
        let room = story(startDay: 1, filled: 2, total: 3)

        XCTAssertEqual(
            ClipFiling.candidates(in: [full, room], orientation: .portrait).map(\.id),
            [room.id])
    }

    /// One empty slot is enough to be worth offering.
    func testAStoryWithOneSlotLeftIsStillACandidate() {
        let nearlyFull = story(startDay: 1, filled: 2, total: 3)

        XCTAssertEqual(
            ClipFiling.candidates(in: [nearlyFull], orientation: .portrait).count, 1)
    }

    // MARK: - Target day

    func testClipLandsInTheFirstEmptySlot() {
        let partly = story(startDay: 1, filled: 2, total: 3)

        XCTAssertEqual(ClipFiling.targetDay(in: partly), 3)
    }

    /// Gaps count: day 2 being empty means day 2, not day 4.
    func testAGapIsFilledBeforeTheEnd() {
        var gapped = story(startDay: 1, filled: 3, total: 3)
        gapped.cards[1].clipFileName = nil

        XCTAssertEqual(ClipFiling.targetDay(in: gapped), 2)
    }

    /// The whole fix in one assertion. This used to answer "day 3" — a day that
    /// already held a clip — and the caller wrote over it.
    func testAFullStoryHasNowhereToPutIt() {
        let full = story(startDay: 1, filled: 3, total: 3)

        XCTAssertNil(ClipFiling.targetDay(in: full))
    }

    /// A story with no cards at all can't take a clip either, and mustn't
    /// answer "day 1" for a card that doesn't exist.
    func testAStoryWithNoSlotsHasNowhereToPutItEither() {
        var empty = story(startDay: 1, total: 1)
        empty.cards = []

        XCTAssertNil(ClipFiling.targetDay(in: empty))
        XCTAssertTrue(ClipFiling.candidates(in: [empty], orientation: .portrait).isEmpty)
    }
}
