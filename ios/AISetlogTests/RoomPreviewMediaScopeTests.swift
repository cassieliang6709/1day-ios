import XCTest
@testable import AISetlog

@MainActor
final class RoomPreviewMediaScopeTests: XCTestCase {
    func testCachesAreIsolatedAndCloseRemovesOnlyOwnedOutputs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mov")
        let a = root.appendingPathComponent("a.mov")
        let b = root.appendingPathComponent("b.mov")
        for url in [source, a, b] { try Data([1, 2, 3]).write(to: url) }
        let first = RoomPreviewMediaScope()
        let second = RoomPreviewMediaScope()
        defer { first.close(); second.close() }
        XCTAssertTrue(first.accept(a, key: "same"))
        XCTAssertNil(second.cached("same"))
        XCTAssertTrue(second.accept(b, key: "same"))
        XCTAssertEqual(first.cached("same"), a)
        first.close()
        first.close()
        XCTAssertNil(first.cached("same"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertEqual(second.cached("same"), b)
        XCTAssertEqual(try Data(contentsOf: source), Data([1, 2, 3]))
        let late = root.appendingPathComponent("late.mov")
        try Data([4]).write(to: late)
        XCTAssertFalse(first.accept(late, key: "same"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: late.path))
    }

    func testRemovedFileIsNeverReturnedFromCache() throws {
        let scope = RoomPreviewMediaScope()
        defer { scope.close() }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: output)
        scope.accept(output, key: "removed")
        try FileManager.default.removeItem(at: output)
        XCTAssertNil(scope.cached("removed"))
    }
}

#if DEBUG || LOCAL_ROOM_CHAT_DEMO
@MainActor
final class LocalRoomDemoOwnerTests: XCTestCase {
    func testRealRuntimeSwitchAndDismissOwnAllFiles() async throws {
        let owner = LocalRoomDemoOwner()
        defer { owner.close() }
        await owner.load(memberCount: 2, chinese: false)
        let first = try XCTUnwrap(owner.runtime)
        let media = try XCTUnwrap(owner.media)
        XCTAssertEqual(first.store.recordedClips(for: first.challengeID).count, 2)
        XCTAssertEqual(first.preferences.string(forKey: AppLanguage.storageKey), AppLanguage.english.rawValue)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: output)
        media.accept(output)
        await owner.load(memberCount: 3, chinese: true)
        XCTAssertTrue(first.isClosed)
        XCTAssertTrue(media.isClosed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let second = try XCTUnwrap(owner.runtime)
        XCTAssertEqual(second.store.recordedClips(for: second.challengeID).count, 3)
        XCTAssertNotEqual(first.challengeID, second.challengeID)
        owner.close()
        XCTAssertTrue(second.isClosed)
        XCTAssertNil(owner.runtime)
        await owner.load(memberCount: 2, chinese: false)
        XCTAssertNil(owner.runtime)
    }

    func testDismissDuringPreparationCannotResurrectRoom() async {
        let owner = LocalRoomDemoOwner()
        let loading = Task { await owner.load(memberCount: 3, chinese: false) }
        await Task.yield()
        owner.close()
        await loading.value
        XCTAssertTrue(owner.isClosed)
        XCTAssertNil(owner.runtime)
        XCTAssertNil(owner.media)
    }
}
#endif
