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

    // MARK: - Target day

    func testClipLandsInTheFirstEmptySlot() {
        let partly = story(startDay: 1, filled: 2, total: 3)

        XCTAssertEqual(
            ClipFiling.targetDay(in: partly, now: date(1), calendar: calendar), 3)
    }

    /// Gaps count: day 2 being empty means day 2, not day 4.
    func testAGapIsFilledBeforeTheEnd() {
        var gapped = story(startDay: 1, filled: 3, total: 3)
        gapped.cards[1].clipFileName = nil

        XCTAssertEqual(
            ClipFiling.targetDay(in: gapped, now: date(1), calendar: calendar), 2)
    }

    func testAFullStoryOverwritesTheDayItIsOn() {
        let full = story(startDay: 1, filled: 3, total: 3)

        XCTAssertEqual(
            ClipFiling.targetDay(in: full, now: date(3), calendar: calendar), 3)
    }

    /// A full story left alone for a fortnight is on "day 15" — clamping is
    /// what keeps that from writing to a card that doesn't exist.
    func testALongAbandonedFullStoryClampsToItsLastDay() {
        let full = story(startDay: 1, filled: 3, total: 3)

        XCTAssertEqual(
            ClipFiling.targetDay(in: full, now: date(20), calendar: calendar), 3)
    }

    /// And a full story whose start date is somehow in the future clamps the
    /// other way, rather than returning day 0.
    func testAFullStoryStartingLaterClampsToItsFirstDay() {
        let full = story(startDay: 10, filled: 3, total: 3)

        XCTAssertEqual(
            ClipFiling.targetDay(in: full, now: date(1), calendar: calendar), 1)
    }
}
