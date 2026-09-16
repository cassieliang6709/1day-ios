import XCTest
@testable import AISetlog

/// Fixed clocks and explicit calendars: never changes the device time zone.
final class SevenDayCalendarBoundaryTests: XCTestCase {
    private func calendar(_ zone: String) throws -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int,
                      in calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func story(start: Date) -> Challenge {
        Challenge(id: UUID(), title: "我的 Seven days", startDate: start,
                  cards: (1...7).map { DayCard(day: $0) }, mode: .sevenDay)
    }

    func testSpringAndFallDSTUseCalendarDaysThroughSeventhDayAndRestart() throws {
        let calendar = try calendar("America/Los_Angeles")
        for (month, day, expectedHours) in [(3, 7, 143.0), (10, 31, 145.0)] {
            let start = try date(2026, month, day, 12, in: calendar)
            let original = story(start: start)
            let restored = try JSONDecoder().decode(Challenge.self, from: JSONEncoder().encode(original))
            let seventh = try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: start))
            XCTAssertEqual(seventh.timeIntervalSince(start) / 3600, expectedHours)
            for offset in 0...6 {
                let now = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
                XCTAssertEqual(HomeHeroChoice(challenges: [restored], now: now, calendar: calendar), .today(restored))
            }
            let eighth = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
            XCTAssertEqual(HomeHeroChoice(challenges: [restored], now: eighth, calendar: calendar), .resume(restored))
            XCTAssertEqual(restored.title, original.title)
            XCTAssertEqual(restored.startDate, start)
        }
    }

    func testSeventhDayExpiresAtLocalMidnightInMultipleZones() throws {
        for zone in ["Asia/Shanghai", "America/Los_Angeles", "Pacific/Auckland", "UTC"] {
            let calendar = try calendar(zone)
            let value = story(start: try date(2026, 9, 1, 23, in: calendar))
            let midnight = try date(2026, 9, 8, 0, in: calendar)
            XCTAssertEqual(HomeHeroChoice(challenges: [value], now: midnight.addingTimeInterval(-1), calendar: calendar), .today(value), zone)
            // Existing morning policy starts a new story once an old week has expired.
            XCTAssertEqual(HomeHeroChoice(challenges: [value], now: midnight, calendar: calendar), .startToday, zone)
            XCTAssertEqual(HomeHeroChoice(challenges: [value], now: try date(2026, 9, 8, 12, in: calendar), calendar: calendar), .resume(value), zone)
        }
    }
}
