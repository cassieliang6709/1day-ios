import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import AISetlog

/// "发给朋友" shares a rendered card, because WeChat refuses plain text
/// ("暂不支持的文件类型"). These pin the two things that fix depends on: the
/// bytes really are a PNG of the promised shape, and the code is on the card.
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
        // The PNG signature — WeChat sniffs the bytes, not just the UTI.
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
        // Spelled out so VoiceOver reads characters, not a nonsense word.
        XCTAssertTrue(content.accessibilityLabel.contains("K 7 Q X 2 M"))
        XCTAssertTrue(content.accessibilityLabel.contains("周末去海边"))
    }

    /// A blank name is not a name: the card leads with the room rather than
    /// "  邀请你一起拍".
    func testABlankInviterIsDropped() {
        let content = RoomInviteCardContent(challenge: room(), inviter: "   ")
        XCTAssertNil(content.inviter)
        XCTAssertFalse(content.headline.hasPrefix(" "))
    }

    /// One representation, PNG. If text crept back in as an export type, the
    /// share sheet could hand WeChat the text again.
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
