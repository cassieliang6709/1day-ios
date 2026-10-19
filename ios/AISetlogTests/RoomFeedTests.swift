import XCTest
@testable import AISetlog

/// The room page's columns (1.5): one per person, me first, every clip of
/// theirs newest first. Pinned here because the order is the whole layout —
/// a column that jumps sideways when somebody films is a page you can't learn.
final class RoomFeedTests: XCTestCase {
    private let myID = "me"

    private func clip(_ author: String, day: Int, minutesAgo: Double, name: String? = nil) -> DayClip {
        DayClip(
            day: day, url: URL(fileURLWithPath: "/tmp/\(author)-\(day)-\(minutesAgo).mov"),
            authorName: name ?? author, authorID: author,
            recordedAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60),
            key: "\(author)-\(day)-\(minutesAgo)")
    }

    func testMeFirstThenMembersByNameEachNewestFirst() {
        let clips = [
            clip("leo", day: 1, minutesAgo: 90),
            clip(myID, day: 1, minutesAgo: 80),
            clip("ana", day: 2, minutesAgo: 10),
            clip(myID, day: 2, minutesAgo: 5),
            clip("leo", day: 2, minutesAgo: 30),
        ]
        let columns = RoomFeed.columns(
            clips: clips,
            members: [("leo", "Leo"), (myID, "Cassie"), ("ana", "Ana")],
            myID: myID)

        XCTAssertEqual(columns.map(\.id), [myID, "ana", "leo"])
        XCTAssertTrue(columns[0].isMine)
        XCTAssertEqual(columns[0].clips.map(\.day), [2, 1])
        XCTAssertEqual(columns[2].clips.map(\.recordedAt), [
            Date(timeIntervalSince1970: 1_000_000 - 30 * 60),
            Date(timeIntervalSince1970: 1_000_000 - 90 * 60),
        ])
    }

    /// A clip filed before the story was shared is authored "local" and is
    /// still mine — it goes in my column, not a column of its own.
    func testLocalAuthorIsMine() {
        let columns = RoomFeed.columns(
            clips: [clip(RoomProgress.soloAuthorID, day: 1, minutesAgo: 1)],
            members: [(myID, "Cassie"), ("ana", "Ana")],
            myID: myID)
        XCTAssertEqual(columns.map(\.id), [myID, "ana"])
        XCTAssertEqual(columns[0].clips.count, 1)
        XCTAssertTrue(columns[1].clips.isEmpty)
    }

    /// Somebody whose footage arrived before their membership still gets a
    /// column, after the members.
    func testAuthorMissingFromMembersStillGetsAColumn() {
        let columns = RoomFeed.columns(
            clips: [clip("bo", day: 1, minutesAgo: 3, name: "Bo")],
            members: [(myID, "Cassie"), ("ana", "Ana")],
            myID: myID)
        XCTAssertEqual(columns.map(\.id), [myID, "ana", "bo"])
        XCTAssertEqual(columns[2].name, "Bo")
    }

    /// The page always has my column, even before I'm in `members`.
    func testMyColumnExistsWithNoMembers() {
        let columns = RoomFeed.columns(clips: [], members: [], myID: myID)
        XCTAssertEqual(columns.map(\.id), [myID])
        XCTAssertTrue(columns[0].clips.isEmpty)
    }

    /// 2:07 used to show as "02:7": the hour was padded, the minute wasn't.
    func testRoomClockPadsTheMinute() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 19, hour: 2, minute: 7)))
        for id in ["zh-Hans", "en_US"] {
            var style = Date.FormatStyle.roomClock
            style.timeZone = calendar.timeZone
            XCTAssertEqual(date.formatted(style.locale(Locale(identifier: id))), "02:07", id)
        }
    }
}
