import XCTest
@testable import AISetlog

final class ChallengeStateTests: XCTestCase {
    func testDayCardStatesCoverDoneTodayMissedAndLocked() {
        XCTAssertEqual(DayCard(day: 1, clipFileName: "day1.mov").status(currentDay: 2), .done)
        XCTAssertEqual(DayCard(day: 2).status(currentDay: 2), .today)
        XCTAssertEqual(DayCard(day: 1).status(currentDay: 2), .missed)
        XCTAssertEqual(DayCard(day: 3).status(currentDay: 2), .locked)
    }

    func testChallengeCompletionTracksRecordedCards() {
        let challenge = Challenge(
            id: UUID(),
            title: "Morning routine",
            startDate: .now,
            cards: [
                DayCard(day: 1, clipFileName: "day1.mov"),
                DayCard(day: 2, clipFileName: "day2.mov"),
            ]
        )

        XCTAssertEqual(challenge.recordedCount, 2)
        XCTAssertTrue(challenge.isComplete)
    }

    func testOneDayChallengeTreatsOpenMomentsAsToday() {
        let challenge = Challenge(
            id: UUID(),
            title: "Soft reset",
            startDate: .now,
            cards: [DayCard(day: 1), DayCard(day: 2)],
            mode: .oneDay
        )

        XCTAssertEqual(challenge.cardStatus(challenge.cards[0]), .today)
        XCTAssertEqual(challenge.cardStatus(challenge.cards[1]), .today)
    }

    func testCustomMomentTitlesDriveLabels() {
        let challenge = Challenge(
            id: UUID(),
            title: "Deep focus",
            startDate: .now,
            cards: [DayCard(day: 1), DayCard(day: 2)],
            momentTitles: ["Setup", "Solved bit"]
        )

        XCTAssertEqual(challenge.title(forSlot: 1), "Setup")
        XCTAssertEqual(challenge.title(forSlot: 2), "Solved bit")
        XCTAssertEqual(challenge.title(forSlot: 3), "Day 3")
    }
}
