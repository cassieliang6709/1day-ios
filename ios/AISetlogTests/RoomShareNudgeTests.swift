import XCTest
@testable import AISetlog

/// A room is created empty and then invited to, and the gap between those two
/// is where rooms died — nothing on the story page said *now*. See
/// `docs/ux-audit-2026-09-09.md` 3.1.
///
/// The offer therefore has to be exactly once. The story page is rebuilt on
/// every navigation back to it, so "once" cannot live in `@State`, and a nudge
/// that reappears on the fourth visit is nagging rather than helping.
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

    /// The assertion the feature is for. Marking happens when the dialog is
    /// *raised*, not when it is answered, because "待会儿" is an answer.
    func testItIsOnlyEverOfferedOnce() {
        RoomShareNudge.markOffered(code: "ABC123")
        XCTAssertFalse(RoomShareNudge.shouldOffer(code: "ABC123", isEmptyRoom: true))
    }

    /// A room a friend has already joined has had its invitation delivered.
    /// Telling the owner to send the code over the top of that is the app not
    /// watching what happened.
    func testARoomSomebodyJoinedIsNotOffered() {
        XCTAssertFalse(RoomShareNudge.shouldOffer(code: "ABC123", isEmptyRoom: false))
    }

    /// Keyed by code, so two rooms are two decisions.
    func testOfferingOneRoomDoesNotSilenceAnother() {
        RoomShareNudge.markOffered(code: "ABC123")
        XCTAssertTrue(RoomShareNudge.shouldOffer(code: "XYZ789", isEmptyRoom: true))
    }

    /// Marking twice is not an error, and does not un-mark.
    func testMarkingTwiceIsHarmless() {
        RoomShareNudge.markOffered(code: "ABC123")
        RoomShareNudge.markOffered(code: "ABC123")
        XCTAssertFalse(RoomShareNudge.shouldOffer(code: "ABC123", isEmptyRoom: true))
    }
}
