import XCTest
@testable import AISetlog

final class InviteBoundaryRegressionTests: XCTestCase {
    func testPasteNeverSalvagesPrefixOrSuffixOfMalformedCode() {
        for code in ["KPADC77", "KPADC70", "0KPADC7", "IKPADC7", "KPADC7O", "KPADC7XYZ"] {
            XCTAssertNil(InviteCode.extract(from: code), code)
            XCTAssertNil(InviteCode.extract(from: "oneday://join?code=\(code)"), code)
            XCTAssertNil(InviteCode.fromDeepLink(URL(string: "oneday://join?code=\(code)")!), code)
        }
    }

    func testTypedDedicatedPasteAndDeepLinkAgreeForValidCodes() {
        for code in ["kpadc7", "gpp5rl", "ab2345"] {
            let typed = InviteCode.normalize(code)
            XCTAssertTrue(InviteCode.isValid(typed))
            XCTAssertEqual(InviteCode.extract(from: "邀请码：\(code)！"), typed)
            XCTAssertEqual(InviteCode.extract(from: "oneday://join?code=\(code)&from=chat"), typed)
            XCTAssertEqual(InviteCode.fromDeepLink(URL(string: "oneday://join?code=\(code)&from=chat")!), typed)
        }
    }

    func testLinkCodeStillTakesPriorityOverSixLetterStoryTitle() {
        XCTAssertEqual(InviteCode.extract(from: "ABCDEF 邀请你 oneday://join?code=KPADC7"), "KPADC7")
        XCTAssertEqual(InviteCode.extract(from: "无效 KPADC70；有效 GPP5RL"), "GPP5RL")
    }
}
