import XCTest
@testable import AISetlog

final class DestructiveActionGuardTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    private func inChinese() { UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey) }
    private func inEnglish() { UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey) }


    func testDeletingAStorySaysHowManyClipsGoWithIt() {
        inChinese()
        XCTAssertTrue(Strings.deleteStoryWarning(3).contains("3"))
        inEnglish()
        XCTAssertTrue(Strings.deleteStoryWarning(3).contains("3"))
    }

    func testAnEmptyStoryIsNotWarnedAboutClips() {
        for setLanguage in [inChinese, inEnglish] {
            setLanguage()
            XCTAssertFalse(Strings.deleteStoryWarning(0).contains("0"))
        }
    }

    func testEnglishClipCountAgreesWithItsNoun() {
        inEnglish()
        XCTAssertTrue(Strings.deleteStoryWarning(1).contains("1 clip"))
        XCTAssertFalse(Strings.deleteStoryWarning(1).contains("1 clips"))
        XCTAssertTrue(Strings.deleteStoryWarning(2).contains("2 clips"))
    }

    func testTheStoryBeingDeletedIsNamed() {
        for setLanguage in [inChinese, inEnglish] {
            setLanguage()
            XCTAssertTrue(Strings.deleteStoryTitle("Gym Week").contains("Gym Week"))
            XCTAssertTrue(Strings.leaveRoomTitle("Gym Week").contains("Gym Week"))
        }
    }


    func testLeavingARoomWarnsTheClipsAreDeleted() {
        inChinese()
        let zh = Strings.leaveRoomWarning
        XCTAssertTrue(zh.contains("删掉"))
        XCTAssertTrue(zh.contains("找不回来"))
        XCTAssertNotEqual(zh, Strings.deleteStoryWarning(3))

        inEnglish()
        let en = Strings.leaveRoomWarning
        XCTAssertTrue(en.lowercased().contains("deleted"))
        XCTAssertTrue(en.lowercased().contains("for good"))
        XCTAssertNotEqual(en, Strings.deleteStoryWarning(3))
    }


    func testTheKeepOrDiscardFootnoteSaysWhereKeepPutsIt() {
        inChinese()
        XCTAssertTrue(Strings.keepClipFootnote.contains("我的"))
        inEnglish()
        XCTAssertTrue(Strings.keepClipFootnote.contains("Mine"))
    }


    func testDeniedCameraIsWordedDifferentlyFromAnUnavailableOne() {
        for setLanguage in [inChinese, inEnglish] {
            setLanguage()
            XCTAssertNotEqual(Strings.cameraDeniedTitle, Strings.cameraUnavailable)
            XCTAssertFalse(Strings.cameraDeniedFootnote.isEmpty)
        }
        inChinese()
        XCTAssertTrue(Strings.cameraDeniedFootnote.contains("设置"))
        inEnglish()
        XCTAssertTrue(Strings.cameraDeniedFootnote.contains("Settings"))
    }


    func testEveryNewWarningIsWrittenInBothLanguages() {
        inChinese()
        let zh = [
            Strings.deleteStoryTitle("X"), Strings.deleteStoryWarning(2),
            Strings.leaveRoomTitle("X"), Strings.leaveRoomWarning,
            Strings.keepClipFootnote, Strings.cameraDeniedTitle,
            Strings.cameraDeniedFootnote,
        ]
        inEnglish()
        let en = [
            Strings.deleteStoryTitle("X"), Strings.deleteStoryWarning(2),
            Strings.leaveRoomTitle("X"), Strings.leaveRoomWarning,
            Strings.keepClipFootnote, Strings.cameraDeniedTitle,
            Strings.cameraDeniedFootnote,
        ]
        for (index, pair) in zip(zh, en).enumerated() {
            XCTAssertNotEqual(pair.0, pair.1, "string \(index) is the same in both languages")
        }
    }
}
