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

    func testFiltersMineAndFriends() {
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
        // Newest first.
        XCTAssertEqual(library.clips.map(\.recordedAt.timeIntervalSince1970), [300, 200, 100])
    }

    private func cameraLibrary() -> (ClipLibrary, [String: CameraStyle]) {
        let s = story("A", shared: true)
        func at(_ seconds: TimeInterval, _ author: String) -> DayClip {
            DayClip(day: 1, url: URL(fileURLWithPath: "/tmp/\(Int(seconds)).mov"),
                    authorName: nil, authorID: author,
                    recordedAt: Date(timeIntervalSince1970: seconds))
        }
        let library = ClipLibrary(
            stories: [(s, [at(1, me), at(2, me), at(3, "friend"), at(4, me), at(5, me)])],
            drafts: [], myIDs: [me])
        var cameras: [String: CameraStyle] = [:]
        for item in library.clips {
            switch Int(item.recordedAt.timeIntervalSince1970) {
            case 1, 3: cameras[item.cameraKey] = .film
            case 2: cameras[item.cameraKey] = .instant
            case 4: cameras[item.cameraKey] = .standard
            default: break // 5: metadata not read yet
            }
        }
        return (library, cameras)
    }

    func testFiltersByCamera() {
        let (library, cameras) = cameraLibrary()
        XCTAssertEqual(library.filtered(.all, cameras: cameras).count, 5)
        XCTAssertEqual(library.filtered(.camera(.film), cameras: cameras).count, 2)
        XCTAssertEqual(library.filtered(.camera(.instant), cameras: cameras).count, 1)
        XCTAssertEqual(library.filtered(.camera(.camcorder), cameras: cameras).count, 0)
        // A clip whose camera hasn't been read matches no camera.
        XCTAssertEqual(library.filtered(.camera(.film)).count, 0)
    }

    func testCameraAndPeopleCombine() {
        let (library, cameras) = cameraLibrary()
        let mineOnFilm = LibraryFilter(camera: .film, people: .mine)
        let friendsOnFilm = LibraryFilter(camera: .film, people: .friends)
        XCTAssertEqual(library.filtered(mineOnFilm, cameras: cameras).count, 1)
        XCTAssertEqual(library.filtered(friendsOnFilm, cameras: cameras).count, 1)
    }

    func testCameraChipsOnlyForUsedCamerasInPickerOrder() {
        let (library, cameras) = cameraLibrary()
        // `.standard` never gets a chip; camcorder has no clips.
        XCTAssertEqual(library.cameras(in: cameras), [.film, .instant])
        XCTAssertEqual(library.cameras(in: [:]), [])
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
