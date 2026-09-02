import XCTest
@testable import AISetlog

/// The numbers this feature exists to produce: do people film what a model
/// tells them to film, and which parts of it do they throw away.
final class PromptSuggestionMetricsTests: XCTestCase {
    private let suite = "prompt-metrics-tests"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func metrics() -> PromptSuggestionMetrics {
        PromptSuggestionMetrics(defaults: defaults)
    }

    func testGeneratingAndAdoptingAreCountedSeparately() {
        let metrics = metrics()

        metrics.recordGenerated()
        metrics.recordGenerated()
        metrics.recordAdopted(offered: ["一", "二"], saved: ["一", "二"])

        XCTAssertEqual(metrics.snapshot.generated, 2)
        XCTAssertEqual(metrics.snapshot.adopted, 1)
        XCTAssertEqual(metrics.snapshot.adoptionRate, 0.5)
    }

    func testAPromptThatSurvivedUnchangedIsNotAnEdit() {
        let metrics = metrics()

        metrics.recordAdopted(offered: ["一", "二", "三"], saved: ["一", "二", "三"])

        XCTAssertEqual(metrics.snapshot.promptsOffered, 3)
        XCTAssertEqual(metrics.snapshot.promptsEdited, 0)
        XCTAssertEqual(metrics.snapshot.editRate, 0)
        XCTAssertTrue(metrics.snapshot.editsByPosition.isEmpty)
    }

    /// Which slots get rewritten is the interesting half. If it's always the
    /// last two, the model is bad at endings, not bad at prompts.
    func testEditsAreRecordedByPosition() {
        let metrics = metrics()

        metrics.recordAdopted(
            offered: ["一", "二", "三"],
            saved: ["一", "我改的", "三"])

        XCTAssertEqual(metrics.snapshot.promptsEdited, 1)
        XCTAssertEqual(metrics.snapshot.editsByPosition, [2: 1])
        XCTAssertEqual(metrics.snapshot.editRate, 1.0 / 3.0)
    }

    /// Deleting a prompt is the strongest edit there is, so it counts as one.
    func testADeletedPromptCountsAsAnEdit() {
        let metrics = metrics()

        metrics.recordAdopted(offered: ["一", "二", "三"], saved: ["一", "三"])

        XCTAssertEqual(metrics.snapshot.promptsEdited, 1)
        XCTAssertEqual(metrics.snapshot.editsByPosition, [2: 1])
    }

    /// A story written entirely by hand has nothing to say about the model.
    func testAStoryWithNoGeneratedPromptsIsNotCountedAsAdopted() {
        let metrics = metrics()

        metrics.recordAdopted(offered: [], saved: ["我自己写的", "还有一个"])

        XCTAssertEqual(metrics.snapshot.adopted, 0)
        XCTAssertEqual(metrics.snapshot.promptsOffered, 0)
        XCTAssertNil(metrics.snapshot.editRate)
    }

    func testCountsSurviveALaunch() {
        let first = metrics()
        first.recordGenerated()
        first.recordAdopted(offered: ["一", "二"], saved: ["一", "改过的"])

        let second = metrics()

        XCTAssertEqual(second.snapshot, first.snapshot)
        XCTAssertEqual(second.snapshot.editsByPosition, [2: 1])
    }

    func testResetClearsEverything() {
        let first = metrics()
        first.recordGenerated()
        first.recordAdopted(offered: ["一", "二"], saved: ["一"])

        first.reset()

        XCTAssertEqual(first.snapshot, PromptSuggestionMetrics.Snapshot())
        // And the clearing reached disk, not just this instance.
        XCTAssertEqual(metrics().snapshot, PromptSuggestionMetrics.Snapshot())
    }
}
