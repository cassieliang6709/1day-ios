import XCTest
@testable import AISetlog

/// The share blurb puts the code in the middle of a sentence and repeats it in
/// a deep link. Pasting that used to yield the first six alphanumerics — which
/// on the Chinese blurb meant characters out of "1Day" and the title, and a
/// "no room with that code" dead end.
final class InviteCodeTests: XCTestCase {
    func testExtractsCodeFromEnglishShareBlurb() {
        let blurb = Strings.shareMessageInvite(title: "A perfect day", code: "KPADC7")
        XCTAssertEqual(CloudKitService.extractCode(from: blurb), "KPADC7")
    }

    func testExtractsCodeFromChineseShareBlurb() {
        let blurb = "来 1Day 加入我的「完美的一天」挑战！邀请码：KPADC7\noneday://join?code=KPADC7"
        XCTAssertEqual(CloudKitService.extractCode(from: blurb), "KPADC7")
    }

    func testExtractsBareCodeRegardlessOfCase() {
        XCTAssertEqual(CloudKitService.extractCode(from: "kpadc7"), "KPADC7")
        XCTAssertEqual(CloudKitService.extractCode(from: "  GPP5RL  "), "GPP5RL")
    }

    func testIgnoresRunsThatArentSixCharacters() {
        XCTAssertNil(CloudKitService.extractCode(from: "1Day"))
        XCTAssertNil(CloudKitService.extractCode(from: "ABCDEFG"))
        XCTAssertNil(CloudKitService.extractCode(from: "no code here"))
    }

    /// O/0 and I/1 are absent from the alphabet so codes stay dictatable; a
    /// six-character run containing them isn't a code.
    func testRejectsAmbiguousCharacters() {
        XCTAssertNil(CloudKitService.extractCode(from: "AB0DEF"))
        XCTAssertNil(CloudKitService.extractCode(from: "ABIDEF"))
    }
}
