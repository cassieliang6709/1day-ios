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

    func testStitchableKeepsPickedOrderAndRenumbers() {
        let a = story("A", shared: false)
        let b = story("B", shared: false)
        let library = ClipLibrary(
            stories: [(a, [clip(day: 1, author: me, at: 300)]), (b, [clip(day: 1, author: me, at: 100)])],
            drafts: [], myIDs: [me])
        // Newest first as picked; the vlog plays them in that order.
        let stitched = ClipLibrary.stitchable(library.clips)
        XCTAssertEqual(stitched.map(\.day), [1, 2])
        XCTAssertEqual(stitched.map { $0.recordedAt?.timeIntervalSince1970 }, [300, 100])
        // Dragged into the other order in the arrange sheet.
        let reordered = ClipLibrary.stitchable(library.clips.reversed())
        XCTAssertEqual(reordered.map(\.day), [1, 2])
        XCTAssertEqual(reordered.map { $0.recordedAt?.timeIntervalSince1970 }, [100, 300])
        XCTAssertEqual(reordered.map(\.id), library.clips.reversed().map(\.id))
    }

    private func draft(at seconds: TimeInterval) -> (draft: ClipDraft, url: URL) {
        let d = ClipDraft(
            fileName: "d\(Int(seconds)).mov", recordedAt: Date(timeIntervalSince1970: seconds),
            orientation: .portrait, overlayText: nil, byteSize: 1)
        return (d, URL(fileURLWithPath: "/tmp/d\(Int(seconds)).mov"))
    }

    func testDraftsFilterShowsOnlyUnfiledClips() {
        let s = story("A", shared: true)
        let library = ClipLibrary(
            stories: [(s, [clip(day: 1, author: me, at: 100), clip(day: 2, author: "friend", at: 200)])],
            drafts: [draft(at: 150), draft(at: 50)],
            myIDs: [me])
        XCTAssertEqual(library.draftCount, 2)
        XCTAssertEqual(library.filtered(.all).count, 4)
        let drafts = library.filtered(.drafts)
        XCTAssertEqual(drafts.map(\.recordedAt.timeIntervalSince1970), [150, 50])
        XCTAssertTrue(drafts.allSatisfy { $0.storyID == nil })
        // Drafts are mine, so 朋友拍的 + 待归档 is empty.
        XCTAssertEqual(library.filtered(LibraryFilter(people: .friends, draftsOnly: true)).count, 0)
        XCTAssertEqual(library.filtered(LibraryFilter(people: .mine, draftsOnly: true)).count, 2)
    }

    // MARK: - 含朋友的

    /// Two of mine in a room, one friend's, one draft.
    private func mixedLibrary() -> ClipLibrary {
        let room = story("Trip", shared: true)
        return ClipLibrary(
            stories: [(room, [clip(day: 1, author: me, at: 100), clip(day: 1, author: "friend", at: 200),
                              clip(day: 2, author: me, at: 300)])],
            drafts: [draft(at: 50)],
            myIDs: [me])
    }

    /// 我的 opens on `.archive`: my story clips and my draft, no friend.
    func testArchiveDefaultShowsOnlyMine() {
        let library = mixedLibrary()
        let shown = library.filtered(.archive)
        XCTAssertEqual(shown.count, 3)
        XCTAssertTrue(shown.allSatisfy(\.isMine))
        XCTAssertFalse(LibraryFilter.archive.includesFriends)
        // A bare filter (what a room's feed uses) still means everyone's.
        XCTAssertEqual(library.filtered(.all).count, 4)
    }

    func testIncludeFriendsBringsFriendsBack() {
        let library = mixedLibrary()
        var on = LibraryFilter.archive
        on.includesFriends = true
        XCTAssertEqual(library.filtered(on).count, 4)
        XCTAssertEqual(library.filtered(on).filter { !$0.isMine }.count, 1)
        // The scoped library the page counts and covers from agrees.
        XCTAssertEqual(library.scoped(includingFriends: true).clips.count, 4)
        XCTAssertEqual(library.scoped(includingFriends: false).clips.count, 3)
        // Covers come from what is shown, so with the chip off no day's
        // picture is a friend's clip.
        let covers = library.coverByDay(library.filtered(.archive))
        XCTAssertTrue(covers.values.allSatisfy(\.isMine))
    }

    /// An explicit 朋友拍的 pick shows friends whatever the chip says; 我拍的
    /// is mine either way.
    func testExplicitPeoplePickOverridesChip() {
        let library = mixedLibrary()
        let friendsChipOff = LibraryFilter(people: .friends, includesFriends: false)
        XCTAssertEqual(library.filtered(friendsChipOff).count, 1)
        let mineChipOn = LibraryFilter(people: .mine, includesFriends: true)
        XCTAssertEqual(library.filtered(mineChipOn).count, 3)
    }

    func testDraftsShowWhetherOrNotFriendsAreIncluded() {
        let library = mixedLibrary()
        for includesFriends in [false, true] {
            let filter = LibraryFilter(draftsOnly: true, includesFriends: includesFriends)
            XCTAssertEqual(library.filtered(filter).count, 1)
            XCTAssertEqual(library.scoped(includingFriends: includesFriends).draftCount, 1)
            XCTAssertEqual(
                library.filtered(LibraryFilter(includesFriends: includesFriends))
                    .filter { $0.storyID == nil }.count, 1)
        }
    }

    func testScopedCamerasIgnoreFriendsOnlyCameras() {
        let (library, cameras) = cameraLibrary()
        // Clip 3 (friend) is film, as is clip 1 (mine), so film stays; a
        // camera only the friend used would drop out.
        var friendOnly = cameras
        for item in library.clips where !item.isMine { friendOnly[item.cameraKey] = .camcorder }
        XCTAssertTrue(library.cameras(in: friendOnly).contains(.camcorder))
        XCTAssertFalse(library.scoped(includingFriends: false).cameras(in: friendOnly).contains(.camcorder))
    }

    func testDraftsFilterCombinesWithDay() {
        let s = story("A", shared: false)
        let dayLength: TimeInterval = 86_400
        let library = ClipLibrary(
            stories: [(s, [clip(day: 1, author: me, at: dayLength + 10)])],
            drafts: [draft(at: dayLength + 20), draft(at: dayLength * 3)],
            myIDs: [me])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let onDay = library.filtered(
            .drafts, on: Date(timeIntervalSince1970: dayLength + 5), calendar: calendar)
        XCTAssertEqual(onDay.map(\.recordedAt.timeIntervalSince1970), [dayLength + 20])
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
