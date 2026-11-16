import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import AISetlog

final class RoomInviteCardTests: XCTestCase {
    private func room(title: String = "周末去海边", code: String = "K7QX2M") -> Challenge {
        Challenge(
            id: UUID(), title: title, startDate: Date(timeIntervalSince1970: 0), cards: [],
            roomCode: code)
    }

    @MainActor
    func testRendersAPortraitPNGAtTenEightyByThirteenFifty() throws {
        let content = RoomInviteCardContent(challenge: room(), inviter: "Cassie")
        let data = try RoomInviteCardRenderer.pngData(for: content)

        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        let image = try XCTUnwrap(UIImage(data: data))
        let pixels = CGSize(
            width: image.size.width * image.scale, height: image.size.height * image.scale)
        XCTAssertEqual(pixels.width, 1080, accuracy: 1)
        XCTAssertEqual(pixels.height, 1350, accuracy: 1)
        XCTAssertEqual(pixels.width / pixels.height, 4.0 / 5.0, accuracy: 0.01)
    }

    func testTheCardCarriesTheRoomAndItsCode() {
        let content = RoomInviteCardContent(challenge: room(), inviter: "Cassie")
        XCTAssertEqual(content.code, "K7QX2M")
        XCTAssertEqual(content.title, "周末去海边")
        XCTAssertTrue(content.headline.contains("Cassie"))
        XCTAssertTrue(content.accessibilityLabel.contains("K 7 Q X 2 M"))
        XCTAssertTrue(content.accessibilityLabel.contains("周末去海边"))
    }

    func testABlankInviterIsDropped() {
        let content = RoomInviteCardContent(challenge: room(), inviter: "   ")
        XCTAssertNil(content.inviter)
        XCTAssertFalse(content.headline.hasPrefix(" "))
    }

    func testTheShareItemExportsOnlyPNG() throws {
        guard #available(iOS 18.2, *) else {
            throw XCTSkip("exportedContentTypes() needs iOS 18.2")
        }
        let item = RoomInviteCardImage(content: RoomInviteCardContent(
            title: "T", code: "ABCDEF", inviter: nil))
        let types = item.exportedContentTypes()
        XCTAssertEqual(types, [.png])
    }
}
