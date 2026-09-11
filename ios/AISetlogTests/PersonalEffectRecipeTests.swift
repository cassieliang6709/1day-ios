import XCTest
@testable import AISetlog

final class PersonalEffectRecipeTests: XCTestCase {
    private func recipe(story: UUID = UUID(), clip: String = "day1", author: String = "a") -> PersonalEffectRecipe {
        PersonalEffectRecipe(scope: .init(storyID: story, clipID: clip, authorID: author),
                             schemaVersion: 99, rendererID: "unapproved-future-renderer",
                             payload: Data([0, 255, 42, 10]))
    }

    func testOpaqueFutureRecipeRoundTripsButCannotSilentlyRender() throws {
        let original = recipe()
        let decoded = try JSONDecoder().decode(PersonalEffectRecipe.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        var selection = PersonalEffectSelection(scope: original.scope, sourceURL: URL(fileURLWithPath: "/unused/source.mov"))
        try selection.set(decoded, currentAuthorID: "a")
        XCTAssertThrowsError(try selection.renderRecipe { _, _ in false }) {
            XCTAssertEqual($0 as? PersonalEffectRecipe.ValidationError, .unsupportedRecipe)
        }
        XCTAssertEqual(selection.recipe, original)
        let preview = try selection.renderRecipe { $0 == 99 && $1 == original.rendererID }
        let export = try selection.renderRecipe { $0 == 99 && $1 == original.rendererID }
        XCTAssertEqual(preview, export)
    }

    func testStoryClipAndAuthorIsolationAndFailedEditAtomicity() throws {
        let original = recipe()
        var selection = PersonalEffectSelection(scope: original.scope, sourceURL: URL(fileURLWithPath: "/unused/source.mov"))
        try selection.set(original, currentAuthorID: "a")
        for candidate in [recipe(), recipe(story: original.scope.storyID, clip: "day2"),
                          recipe(story: original.scope.storyID, author: "b")] {
            XCTAssertThrowsError(try selection.set(candidate, currentAuthorID: candidate.scope.authorID))
            XCTAssertEqual(selection.recipe, original)
        }
        for editor: String? in [nil, "", "b"] {
            XCTAssertThrowsError(try selection.set(original, currentAuthorID: editor))
            XCTAssertThrowsError(try selection.reset(currentAuthorID: editor))
            XCTAssertEqual(selection.recipe, original)
        }
        try selection.reset(currentAuthorID: "a")
        XCTAssertNil(try selection.renderRecipe { _, _ in false })
    }

    func testSelectionAndResetNeverModifySourceBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let bytes = Data("read-only fixture, not real user footage".utf8)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = recipe()
        var selection = PersonalEffectSelection(scope: original.scope, sourceURL: url)
        try selection.set(original, currentAuthorID: "a")
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        try selection.reset(currentAuthorID: "a")
        XCTAssertEqual(selection.sourceURL, url)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let anonymous = recipe(author: "")
        XCTAssertThrowsError(try anonymous.validateEditor(""))
    }
}
