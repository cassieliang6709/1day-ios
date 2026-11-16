import XCTest
@testable import AISetlog

final class InviteCodeTests: XCTestCase {
    func testExtractsCodeFromEnglishShareBlurb() {
        let blurb = Strings.shareMessageInvite(title: "A perfect day", code: "KPADC7")
        XCTAssertEqual(InviteCode.extract(from: blurb), "KPADC7")
    }

    func testExtractsCodeFromChineseShareBlurb() {
        let blurb = "来 1Day 加入我的「完美的一天」挑战！邀请码：KPADC7\noneday://join?code=KPADC7"
        XCTAssertEqual(InviteCode.extract(from: blurb), "KPADC7")
    }

    func testExtractsBareCodeRegardlessOfCase() {
        XCTAssertEqual(InviteCode.extract(from: "kpadc7"), "KPADC7")
        XCTAssertEqual(InviteCode.extract(from: "  GPP5RL  "), "GPP5RL")
    }

    func testIgnoresRunsThatArentSixCharacters() {
        XCTAssertNil(InviteCode.extract(from: "1Day"))
        XCTAssertNil(InviteCode.extract(from: "ABCDEFG"))
        XCTAssertNil(InviteCode.extract(from: "no code here"))
    }

    func testRejectsAmbiguousCharacters() {
        XCTAssertNil(InviteCode.extract(from: "AB0DEF"))
        XCTAssertNil(InviteCode.extract(from: "ABIDEF"))
    }


    func testEveryGeneratedCodeIsOneTheAppWillAccept() {
        for _ in 0..<500 {
            let code = InviteCode.make()
            XCTAssertEqual(code.count, InviteCode.length)
            XCTAssertTrue(InviteCode.isValid(code), "generated an unusable code: \(code)")
            XCTAssertEqual(InviteCode.normalize(code), code)
        }
    }

    func testTheAlphabetLeavesOutEverythingYouCouldMishear() {
        for character in "O0I1" {
            XCTAssertFalse(
                InviteCode.alphabet.contains(character),
                "\(character) is too easy to mishear to be in a code")
        }
        XCTAssertEqual(Set(InviteCode.alphabet).count, InviteCode.alphabet.count)
    }

    func testCodesArentAllTheSame() {
        let codes = Set((0..<50).map { _ in InviteCode.make() })
        XCTAssertGreaterThan(codes.count, 40)
    }


    func testTheFieldUppercasesAndDropsPunctuation() {
        XCTAssertEqual(InviteCode.normalize("kp-adc7"), "KPADC7")
        XCTAssertEqual(InviteCode.normalize(" kp adc 7 "), "KPADC7")
        XCTAssertEqual(InviteCode.normalize("KPADC7"), "KPADC7")
    }

    func testTheFieldStopsAtSix() {
        XCTAssertEqual(InviteCode.normalize("KPADC7XYZ"), "KPADC7")
        XCTAssertTrue(InviteCode.isComplete("KPADC7XYZ"))
    }

    func testTheFieldDoesNotFillWithCharactersACodeCantContain() {
        XCTAssertEqual(InviteCode.normalize("邀请码KPADC7"), "KPADC7")
        XCTAssertEqual(InviteCode.normalize("邀请码在这里"), "")
        XCTAssertFalse(InviteCode.isComplete("邀请码在这里"))
    }

    func testAHalfTypedCodeIsKeptButNotComplete() {
        XCTAssertEqual(InviteCode.normalize("KPA"), "KPA")
        XCTAssertFalse(InviteCode.isComplete("KPA"))
        XCTAssertEqual(InviteCode.normalize("AB0DEF"), "AB0DEF")
        XCTAssertTrue(InviteCode.isComplete("AB0DEF"), "the slots are full even though the code is wrong")
        XCTAssertFalse(InviteCode.isValid("AB0DEF"), "but it is not a code")
    }

    func testAnEmptyFieldIsNotACode() {
        XCTAssertEqual(InviteCode.normalize(""), "")
        XCTAssertFalse(InviteCode.isComplete(""))
        XCTAssertFalse(InviteCode.isValid(""))
    }


    func testValidityIsExactlySixCharactersFromTheAlphabet() {
        XCTAssertTrue(InviteCode.isValid("KPADC7"))
        XCTAssertFalse(InviteCode.isValid("KPADC"), "five is not a code")
        XCTAssertFalse(InviteCode.isValid("KPADC77"), "seven is not a code")
        XCTAssertFalse(InviteCode.isValid("kpadc7"), "lowercase has to be normalized first")
        XCTAssertFalse(InviteCode.isValid("KPAD 7"))
        XCTAssertFalse(InviteCode.isValid("AB0DEF"))
        XCTAssertFalse(InviteCode.isValid("ABIDEF"))
    }


    func testAJoinLinkYieldsItsCode() {
        XCTAssertEqual(
            InviteCode.fromDeepLink(URL(string: "oneday://join?code=KPADC7")!), "KPADC7")
    }

    func testALinkFromAMessageAppSurvivesCaseAndExtraQuery() {
        XCTAssertEqual(
            InviteCode.fromDeepLink(URL(string: "ONEDAY://JOIN?code=kpadc7")!), "KPADC7")
        XCTAssertEqual(
            InviteCode.fromDeepLink(URL(string: "oneday://join?from=sms&code=KPADC7")!), "KPADC7")
    }

    func testALinkWithoutACodeOpensNothing() {
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "oneday://join")!))
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "oneday://join?code=")!))
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "oneday://join?room=KPADC7")!))
    }

    func testAnotherAppsLinkIsNotAJoin() {
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "https://join?code=KPADC7")!))
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "twoday://join?code=KPADC7")!))
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "oneday://open?code=KPADC7")!))
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "oneday://elsewhere?code=KPADC7")!))
    }

    func testALinkCarryingSomethingThatIsntACodeOpensNothing() {
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "oneday://join?code=KPADC")!))
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "oneday://join?code=KPADC77")!))
        XCTAssertNil(InviteCode.fromDeepLink(URL(string: "oneday://join?code=AB0DEF")!))
        XCTAssertNil(InviteCode.fromDeepLink(
            URL(string: "oneday://join?code=\(String(repeating: "A", count: 5000))")!))
    }

    func testTheBlurbAndItsLinkAgree() {
        let code = InviteCode.make()
        let blurb = Strings.shareMessageInvite(title: "A perfect day", code: code)
        XCTAssertEqual(InviteCode.extract(from: blurb), code)
        if let link = InviteCode.extract(from: blurb).map({ URL(string: "oneday://join?code=\($0)")! }) {
            XCTAssertEqual(InviteCode.fromDeepLink(link), code)
        }
    }
}
