import XCTest
@testable import AISetlog

/// The copy on the three "are you sure" dialogs.
///
/// A confirmation is only worth the tap it costs if it says the right thing.
/// Two of these used to say nothing at all — deleting a story and leaving a
/// room were the same menu item, went straight through with no dialog, and had
/// opposite consequences. The wording is what carries that difference, so it is
/// what gets pinned here.
///
/// `ChallengeStore.delete` is the source of truth these assertions are written
/// against: it deletes local clip files, clears the room locally, and leaves the
/// shared CloudKit records alone.
final class DestructiveActionGuardTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    private func inChinese() { UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey) }
    private func inEnglish() { UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey) }

    // MARK: Deleting a story

    func testDeletingAStorySaysHowManyClipsGoWithIt() {
        inChinese()
        XCTAssertTrue(Strings.deleteStoryWarning(3).contains("3"))
        inEnglish()
        XCTAssertTrue(Strings.deleteStoryWarning(3).contains("3"))
    }

    /// A story with nothing filmed has no clips to warn about, and claiming
    /// "0 clips will be deleted" reads like a bug.
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

    // MARK: Leaving a room

    /// The assertion that keeps the two apart. Leaving a room does not delete
    /// anything shared — `ChallengeStore.delete` only calls `clearRoom` — so
    /// the warning must not read like the story-deletion one, and must say the
    /// clips survive.
    func testLeavingARoomPromisesTheClipsStayForEveryoneElse() {
        inChinese()
        let zh = Strings.leaveRoomWarning
        XCTAssertTrue(zh.contains("还留在") || zh.contains("其他人"))
        XCTAssertFalse(zh.contains("找不回来"))
        XCTAssertNotEqual(zh, Strings.deleteStoryWarning(3))

        inEnglish()
        let en = Strings.leaveRoomWarning
        XCTAssertTrue(en.lowercased().contains("stay"))
        XCTAssertFalse(en.lowercased().contains("can't be undone"))
        XCTAssertNotEqual(en, Strings.deleteStoryWarning(3))
    }

    // MARK: Leaving the camera with a clip in review

    /// "Keep" and "Discard" on their own are a coin toss — keep it *where*?
    /// The footnote is the part that makes the choice answerable.
    func testTheKeepOrDiscardFootnoteSaysWhereKeepPutsIt() {
        inChinese()
        XCTAssertTrue(Strings.keepClipFootnote.contains("草稿"))
        inEnglish()
        XCTAssertTrue(Strings.keepClipFootnote.lowercased().contains("draft"))
    }

    // MARK: Camera permission

    /// Denied and unavailable need different words because they need different
    /// actions: iOS never re-asks, so "try again" on a denied camera is a
    /// button that cannot work, and the only way out is Settings.
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

    // MARK: Both languages

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
