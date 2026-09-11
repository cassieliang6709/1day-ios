import XCTest
@testable import AISetlog

/// Exercises the composed runtime used by StoryTimelineView, not a lookalike
/// room or a second live store with a fake room code.
@MainActor
final class LocalRoomRuntimeBoundaryTests: XCTestCase {
    func testClosingOneFormalRoomInvalidatesItsChatWithoutTouchingOtherRuntime() async throws {
        let epoch = AccountStore.identityRevision
        let first = try await LocalRoomRuntime.make(memberCount: 2, chinese: false)
        let second = try await LocalRoomRuntime.make(memberCount: 3, chinese: true)
        defer { first.close(); second.close() }
        let forbidden = RoomChatSessionSource.LiveDependencies(
            directory: { XCTFail("preview read live archive directory"); return first.storage.root },
            transport: { XCTFail("preview constructed live transport"); return first.chat },
            identityLease: { _ in XCTFail("preview read live account"); return { false } })
        let firstRoute = RoomChatSessionSource.local(first.chat)
        let secondRoute = RoomChatSessionSource.local(second.chat)
        let a = firstRoute.makeSession(scope: first.chat.scope, live: forbidden)
        let b = secondRoute.makeSession(scope: second.chat.scope, live: forbidden)
        await a.refresh()
        await b.refresh()
        a.setDraft("First private draft")
        b.setDraft("第二间 private draft")
        first.preferences.set("first", forKey: "selectedFilmLayout")
        second.preferences.set("second", forKey: "selectedFilmLayout")
        first.account.rename(to: "Local renamed")
        XCTAssertEqual(first.account.account?.displayName, "Local renamed")
        XCTAssertNotEqual(second.account.account?.displayName, "Local renamed")
        XCTAssertEqual(AccountStore.identityRevision, epoch)
        XCTAssertNotEqual(firstRoute.identity, secondRoute.identity)
        let secondURLs = second.store.recordedClips(for: second.challengeID).map(\.url)
        let firstRoot = first.storage.root
        let firstArchive = first.chat.directory

        first.close()
        // Retained production chat sessions and a retained store may still get
        // UI tasks after dismissal. None may recreate the closed local scope.
        a.setDraft("late draft")
        await a.send(authorName: "Late")
        await a.refresh()
        await first.store.syncRoom(first.challengeID)
        XCTAssertNil(a.state)
        XCTAssertTrue(first.store.challenges.isEmpty)
        XCTAssertFalse(first.account.isSignedIn)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstArchive.path))
        XCTAssertNil(first.preferences.string(forKey: "selectedFilmLayout"))
        XCTAssertEqual(AccountStore.identityRevision, epoch)

        XCTAssertTrue(second.account.isSignedIn)
        XCTAssertEqual(second.preferences.string(forKey: "selectedFilmLayout"), "second")
        XCTAssertEqual(b.state?.draft, "第二间 private draft")
        XCTAssertTrue(secondURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        await second.store.syncRoom(second.challengeID)
        XCTAssertEqual(second.store.recordedClips(for: second.challengeID).map(\.url), secondURLs)
        await b.send(authorName: "Second")
        let restored = secondRoute.makeSession(scope: second.chat.scope, live: forbidden)
        XCTAssertTrue(restored.state?.orderedEntries.contains { $0.message.text == "第二间 private draft" } == true)
        XCTAssertFalse(restored.state?.orderedEntries.contains { $0.message.text == "First private draft" || $0.message.text == "late draft" } == true)
        XCTAssertEqual(restored.state?.draft, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstArchive.path))
    }
}
