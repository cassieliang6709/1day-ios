import XCTest
@testable import AISetlog

final class RoomShareNudgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RoomShareNudge.reset()
    }

    override func tearDown() {
        RoomShareNudge.reset()
        super.tearDown()
    }

    func testAFreshEmptyRoomIsOffered() {
        XCTAssertTrue(RoomShareNudge.shouldOffer(code: "ABC123", isEmptyRoom: true))
    }

    func testItIsOnlyEverOfferedOnce() {
        RoomShareNudge.markOffered(code: "ABC123")
        XCTAssertFalse(RoomShareNudge.shouldOffer(code: "ABC123", isEmptyRoom: true))
    }

    func testARoomSomebodyJoinedIsNotOffered() {
        XCTAssertFalse(RoomShareNudge.shouldOffer(code: "ABC123", isEmptyRoom: false))
    }

    func testOfferingOneRoomDoesNotSilenceAnother() {
        RoomShareNudge.markOffered(code: "ABC123")
        XCTAssertTrue(RoomShareNudge.shouldOffer(code: "XYZ789", isEmptyRoom: true))
    }

    func testMarkingTwiceIsHarmless() {
        RoomShareNudge.markOffered(code: "ABC123")
        RoomShareNudge.markOffered(code: "ABC123")
        XCTAssertFalse(RoomShareNudge.shouldOffer(code: "ABC123", isEmptyRoom: true))
    }
}
