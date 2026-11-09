import SwiftUI
import XCTest
@testable import AISetlog

final class RoomAvatarLayoutTests: XCTestCase {
    func testEveryMemberHasADistinctVisibleFace() {
        for count in 1...18 {
            let layout = RoomAvatarLayout(memberCount: count)
            XCTAssertEqual(layout.centers.count, count)
            XCTAssertGreaterThan(layout.diameter, 0)
            for (index, center) in layout.centers.enumerated() {
                XCTAssertFalse(layout.centers.prefix(index).contains(center))
                let radius = layout.diameter / 2
                XCTAssertGreaterThanOrEqual(center.x - radius, 0)
                XCTAssertLessThanOrEqual(center.x + radius, RoomAvatarLayout.width)
                XCTAssertGreaterThanOrEqual(center.y - radius, 0)
                XCTAssertLessThanOrEqual(center.y + radius, RoomAvatarLayout.height)
            }
        }
    }

    func testFourAndSixMakeTwoRowsOfEqualLength() {
        for count in [4, 6] {
            let points = RoomAvatarLayout(memberCount: count).centers
            let rows = Dictionary(grouping: points, by: \.y).values
            XCTAssertEqual(rows.count, 2)
            XCTAssertTrue(rows.allSatisfy { $0.count == count / 2 })
            XCTAssertEqual(Set(points.map(\.x)).count, count / 2)
        }
    }

    func testFiveMakesThreeUpperAndTwoInterleavedLowerRings() {
        let points = RoomAvatarLayout(memberCount: 5).centers
        let rows = Dictionary(grouping: points, by: \.y).sorted { $0.key < $1.key }
        XCTAssertEqual(rows.map { $0.value.count }, [3, 2])
        let upper = rows[0].value.map(\.x).sorted()
        let lower = rows[1].value.map(\.x).sorted()
        XCTAssertTrue(upper[0] < lower[0] && lower[0] < upper[1])
        XCTAssertTrue(upper[1] < lower[1] && lower[1] < upper[2])
    }

    @MainActor
    func testRenderAllRoomSizesForVisualReview() throws {
        let content = VStack(alignment: .leading, spacing: 22) {
            ForEach(1...6, id: \.self) { count in
                HStack(spacing: 24) {
                    RoomAvatarCluster(members: Array(["Cassie", "Nini", "Ana", "Bo", "Cy", "Di"].prefix(count))
                        .enumerated().map { (id: String($0.offset), name: $0.element) })
                    Text("\(count) people").foregroundStyle(.black)
                }
            }
        }
        .padding(28)
        .background(Color(red: 1, green: 0.97, blue: 0.89))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "room-avatar-layouts-1-to-6"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class RoomDefaultNameTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    func testChineseDefaultAvoidsExistingNamesIncludingWhitespace() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.defaultRoomName(existingTitles: []), "一起的日常")
        XCTAssertEqual(Strings.defaultRoomName(existingTitles: [" 一起的日常 ", "一起的日常 2", "朋友们"]),
                       "一起的日常 3")
    }

    func testEnglishDefaultAvoidsExistingNames() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.defaultRoomName(existingTitles: []), "Our everyday")
        XCTAssertEqual(Strings.defaultRoomName(existingTitles: ["Our everyday", "Our everyday 2"]),
                       "Our everyday 3")
    }
}

final class UnfiledClipGuardTests: XCTestCase {
    func testFailedPersistenceKeepsTheTakeAndBlocksNavigation() {
        let guardState = UnfiledClipGuard()
        guardState.hasUnfiledClip = true
        guardState.keep = { false }
        XCTAssertFalse(guardState.keepForNavigation())
        XCTAssertTrue(guardState.hasUnfiledClip)
    }

    func testConfirmedPersistenceAllowsLeavingAndClearsThePendingTake() {
        let guardState = UnfiledClipGuard()
        guardState.hasUnfiledClip = true
        guardState.keep = { true }
        XCTAssertTrue(guardState.keepForNavigation())
        XCTAssertFalse(guardState.hasUnfiledClip)
    }
}
