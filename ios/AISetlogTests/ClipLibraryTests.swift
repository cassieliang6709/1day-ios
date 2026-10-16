import XCTest
@testable import AISetlog

final class ClipLibraryTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/x.mov")
    private let me = "me-id"

    private func story(_ title: String, shared: Bool, orientation: Challenge.Orientation = .portrait) -> Challenge {
        Challenge(
            id: UUID(), title: title, startDate: Date(timeIntervalSince1970: 0), cards: [],
            orientation: orientation, roomCode: shared ? "123456" : nil)
    }

    private func clip(day: Int, author: String?, at seconds: TimeInterval) -> DayClip {
        DayClip(day: day, url: url, authorName: author == me ? "Me" : "Friend",
                authorID: author, recordedAt: Date(timeIntervalSince1970: seconds))
    }

    func testFiltersMineFriendsAndRoom() {
        let room = story("Trip", shared: true)
        let solo = story("Solo", shared: false)
        let library = ClipLibrary(
            stories: [
                (room, [clip(day: 1, author: me, at: 100), clip(day: 1, author: "friend", at: 200)]),
                (solo, [clip(day: 1, author: me, at: 300)]),
            ],
            drafts: [],
            myIDs: [me])

        XCTAssertEqual(library.filtered(.all).count, 3)
        XCTAssertEqual(library.filtered(.mine).count, 2)
        XCTAssertEqual(library.filtered(.friends).count, 1)
        XCTAssertEqual(library.filtered(.room(room.id)).count, 2)
        // Newest first.
        XCTAssertEqual(library.clips.map(\.recordedAt.timeIntervalSince1970), [300, 200, 100])
    }

    func testCoverIsEarliestClipOfEachDay() {
        let s = story("A", shared: false)
        let day: TimeInterval = 86_400
        let library = ClipLibrary(
            stories: [(s, [
                clip(day: 1, author: me, at: day + 500),
                clip(day: 2, author: me, at: day + 100),
                clip(day: 3, author: me, at: day * 3 + 50),
            ])],
            drafts: [], myIDs: [me])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let covers = library.coverByDay(library.clips, calendar: calendar)
        XCTAssertEqual(covers.count, 2)
        XCTAssertEqual(
            covers[calendar.startOfDay(for: Date(timeIntervalSince1970: day))]?.recordedAt.timeIntervalSince1970,
            day + 100)
    }

    func testStitchableRenumbersInFilmOrder() {
        let a = story("A", shared: false)
        let b = story("B", shared: false)
        let library = ClipLibrary(
            stories: [(a, [clip(day: 1, author: me, at: 300)]), (b, [clip(day: 1, author: me, at: 100)])],
            drafts: [], myIDs: [me])
        let stitched = ClipLibrary.stitchable(library.clips)
        XCTAssertEqual(stitched.map(\.day), [1, 2])
        XCTAssertEqual(stitched.map { $0.recordedAt?.timeIntervalSince1970 }, [100, 300])
    }

    func testDominantAspectPrefersMajorityThenPortrait() {
        let land = story("L", shared: false, orientation: .landscape)
        let port = story("P", shared: false, orientation: .portrait)
        let two = ClipLibrary(
            stories: [(land, [clip(day: 1, author: me, at: 1), clip(day: 2, author: me, at: 2)]),
                      (port, [clip(day: 1, author: me, at: 3)])],
            drafts: [], myIDs: [me])
        XCTAssertEqual(ClipLibrary.dominantAspect(of: two.clips), .landscape)

        let tie = ClipLibrary(
            stories: [(land, [clip(day: 1, author: me, at: 1)]), (port, [clip(day: 1, author: me, at: 2)])],
            drafts: [], myIDs: [me])
        XCTAssertEqual(ClipLibrary.dominantAspect(of: tie.clips), .portrait)
    }
}
