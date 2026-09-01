import XCTest
@testable import AISetlog

/// The new-story screen's selection state machine. These transitions were
/// previously spread across two selectors that inferred each other's state,
/// which is how a tap on a poster could take you out of "record by time"
/// without the mode cards above ever changing.
final class ComposerSelectionTests: XCTestCase {
    private let oneDay = ChallengeTemplate.oneDayBuiltins
    private let sevenDay = ChallengeTemplate.sevenDayBuiltins

    private var timeOnlyTemplate: ChallengeTemplate {
        oneDay.first(where: \.isTimeOnly)!
    }

    private var perfectDay: ChallengeTemplate {
        oneDay.first { $0.identityKey == "Perfect Day" }!
    }

    func testOpensOnAPromptedStoryWithTheFirstRecommendationChosen() {
        let selection = ComposerSelection.initial(oneDay: oneDay)
        XCTAssertEqual(selection.style, .prompted)
        XCTAssertEqual(selection.mode, .oneDay)
        XCTAssertEqual(selection.templateID, perfectDay.id)
        XCTAssertTrue(selection.promptGridEnabled)
    }

    func testSwitchingToTimeOnlyDisablesTheGridAndPicksLiveWithMe() {
        var selection = ComposerSelection.initial(oneDay: oneDay)
        selection.selectTimeOnly(in: oneDay)

        XCTAssertEqual(selection.style, .timeOnly)
        XCTAssertEqual(selection.templateID, timeOnlyTemplate.id)
        XCTAssertFalse(selection.promptGridEnabled)
    }

    func testSwitchingBackToPromptedLeavesTimeOnlyBehind() {
        var selection = ComposerSelection()
        selection.selectTimeOnly(in: oneDay)
        selection.selectPrompted(in: oneDay)

        XCTAssertEqual(selection.style, .prompted)
        XCTAssertEqual(selection.templateID, perfectDay.id)
        XCTAssertTrue(selection.promptGridEnabled)
    }

    /// The old `selectPromptMode()` returned early whenever a prompted template
    /// was already chosen, so in seven-day mode the tap did nothing at all.
    func testTappingPromptedWhileAlreadyPromptedKeepsTheTemplateAndStaysPrompted() {
        var selection = ComposerSelection()
        let studyStreak = sevenDay.first { $0.identityKey == "Study Streak" }!
        selection.select(studyStreak, oneDay: oneDay, sevenDay: sevenDay)
        XCTAssertEqual(selection.mode, .sevenDay)

        selection.selectPrompted(in: sevenDay)

        XCTAssertEqual(selection.style, .prompted)
        XCTAssertEqual(selection.templateID, studyStreak.id, "should not reshuffle the choice")
    }

    func testPickingASevenDayPosterSwitchesTheMode() {
        var selection = ComposerSelection.initial(oneDay: oneDay)
        let calmWeek = sevenDay.first { $0.identityKey == "Calm Week" }!

        selection.select(calmWeek, oneDay: oneDay, sevenDay: sevenDay)

        XCTAssertEqual(selection.mode, .sevenDay)
        XCTAssertEqual(selection.templateID, calmWeek.id)
        XCTAssertEqual(selection.style, .prompted)
    }

    func testPickingLiveWithMeFromTheGridAlsoFlipsTheModeCards() {
        var selection = ComposerSelection.initial(oneDay: oneDay)
        selection.select(timeOnlyTemplate, oneDay: oneDay, sevenDay: sevenDay)

        XCTAssertEqual(selection.style, .timeOnly)
        XCTAssertFalse(selection.promptGridEnabled)
    }

    /// There is no time-only seven-day template, so the style cannot survive
    /// the switch — the selection has to land on something that exists.
    func testTimeOnlyCannotSurviveASwitchToSevenDay() {
        var selection = ComposerSelection()
        selection.selectTimeOnly(in: oneDay)

        selection.setMode(.sevenDay)
        selection.reconcileTemplate(oneDay: oneDay, sevenDay: sevenDay)

        XCTAssertEqual(selection.mode, .sevenDay)
        XCTAssertEqual(selection.style, .prompted)
        XCTAssertEqual(selection.templateID, sevenDay.first?.id)
    }

    func testReconcileKeepsATemplateThatIsStillValid() {
        var selection = ComposerSelection.initial(oneDay: oneDay)
        let chosen = selection.templateID

        selection.reconcileTemplate(oneDay: oneDay, sevenDay: sevenDay)

        XCTAssertEqual(selection.templateID, chosen)
        XCTAssertEqual(selection.style, .prompted)
    }

    func testGuidedFlowKeepsTheStoryPromptedWithoutATemplate() {
        var selection = ComposerSelection()
        selection.selectTimeOnly(in: oneDay)

        selection.useCustomPrompts()

        XCTAssertEqual(selection.style, .prompted)
        XCTAssertEqual(selection.mode, .oneDay)
        XCTAssertNil(selection.templateID)
    }

    func testDeletingTheChosenTemplateFallsBackToAPromptedBuiltin() {
        var selection = ComposerSelection()
        selection.clearTemplate(fallingBackTo: oneDay)

        XCTAssertEqual(selection.style, .prompted)
        XCTAssertEqual(selection.templateID, perfectDay.id)
        XCTAssertNotEqual(selection.templateID, timeOnlyTemplate.id)
    }
}
