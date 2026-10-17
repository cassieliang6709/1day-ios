import XCTest
@testable import AISetlog

final class PokeLimiterTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "PokeLimiterTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testOncePerPersonPerDay() {
        let limiter = PokeLimiter(defaults: defaults)
        let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9))!
        let evening = morning.addingTimeInterval(60 * 60 * 12)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: morning)!

        XCTAssertFalse(limiter.hasPoked(code: "ROOM", targetAuthorID: "amy", on: morning))
        XCTAssertTrue(limiter.claim(code: "ROOM", targetAuthorID: "amy", on: morning))
        XCTAssertTrue(limiter.hasPoked(code: "ROOM", targetAuthorID: "amy", on: evening))
        XCTAssertFalse(limiter.claim(code: "ROOM", targetAuthorID: "amy", on: evening))

        // A different friend, or the same friend in another room, is separate.
        XCTAssertTrue(limiter.claim(code: "ROOM", targetAuthorID: "ben", on: evening))
        XCTAssertTrue(limiter.claim(code: "OTHER", targetAuthorID: "amy", on: evening))

        // Next day the poke is available again.
        XCTAssertFalse(limiter.hasPoked(code: "ROOM", targetAuthorID: "amy", on: tomorrow))
        XCTAssertTrue(limiter.claim(code: "ROOM", targetAuthorID: "amy", on: tomorrow))
    }

    func testPersistsAcrossInstances() {
        let now = Date.now
        XCTAssertTrue(PokeLimiter(defaults: defaults).claim(code: "ROOM", targetAuthorID: "amy", on: now))
        XCTAssertFalse(PokeLimiter(defaults: defaults).claim(code: "ROOM", targetAuthorID: "amy", on: now))
    }

    func testRecordNameIsPerSenderTargetDay() {
        let a = CloudKitService.pokeRecordName(code: "R", authorID: "me", targetAuthorID: "amy", dayStamp: "2026-10-15")
        let b = CloudKitService.pokeRecordName(code: "R", authorID: "me", targetAuthorID: "amy", dayStamp: "2026-10-16")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, CloudKitService.pokeRecordName(code: "R", authorID: "me", targetAuthorID: "amy", dayStamp: "2026-10-15"))
    }
}
