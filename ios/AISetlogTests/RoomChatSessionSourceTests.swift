import XCTest
import SwiftUI
@testable import AISetlog

@MainActor
final class RoomChatSessionSourceTests: XCTestCase {
    private var forbiddenLive: RoomChatSessionSource.LiveDependencies {
        .init(directory: { XCTFail("Local route read live directory"); return URL(fileURLWithPath: "/unused") },
              transport: { XCTFail("Local route constructed live transport"); return RoomChatDemoTransport(chinese: false) },
              identityLease: { _ in XCTFail("Local route read live identity"); return { false } })
    }

    func testFormalEnvironmentDefaultsLiveAndHonorsLocalOverride() {
        var environment = EnvironmentValues()
        XCTAssertEqual(environment.roomChatSessionSource.identity, "live")
        let preview = RoomChatDemoTransport(chinese: false)
        defer { preview.close() }
        environment.roomChatSessionSource = .local(preview)
        XCTAssertEqual(environment.roomChatSessionSource.identity, preview.directory.absoluteString)
        XCTAssertTrue(environment.roomChatSessionSource.preview === preview)
    }

    func testLocalRouteUsesOnlyLocalArchiveAndInvalidatesOnClose() async {
        let preview = RoomChatDemoTransport(chinese: false)
        defer { preview.close() }
        let source = RoomChatSessionSource.local(preview)
        let session = source.makeSession(scope: preview.scope, live: forbiddenLive)
        await session.refresh()
        XCTAssertEqual(session.state?.entries.count, 6)
        session.setDraft("Local draft 中文")
        let restored = source.makeSession(scope: preview.scope, live: forbiddenLive)
        XCTAssertEqual(restored.state?.draft, "Local draft 中文")
        await restored.send(authorName: "Sample")
        XCTAssertEqual(restored.state?.entries.count, 7)
        preview.close()
        session.setDraft("late")
        await restored.refresh()
        XCTAssertNil(session.state)
        XCTAssertNil(restored.state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.directory.path))
    }

    func testWrongScopeAndClosedLocalNeverFallBackOrCreateArchive() async {
        let preview = RoomChatDemoTransport(chinese: false)
        defer { preview.close() }
        for scope in [RoomChatScope(accountID: "other", roomCode: preview.scope.roomCode),
                      RoomChatScope(accountID: preview.scope.accountID, roomCode: "OTHER")] {
            let session = RoomChatSessionSource.local(preview).makeSession(scope: scope, live: forbiddenLive)
            XCTAssertNil(session.state)
            session.setDraft("must not persist")
            await session.send(authorName: "Other")
            await session.refresh()
            XCTAssertNil(session.state)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.directory.path))
        preview.close()
        let closed = RoomChatSessionSource.local(preview).makeSession(scope: preview.scope, live: forbiddenLive)
        XCTAssertNil(closed.state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.directory.path))
    }

    func testDefaultLiveBranchUsesInjectedTransportDirectoryAndIdentityLease() async {
        let transport = RoomChatDemoTransport(chinese: false)
        defer { transport.close() }
        var valid = true
        var reads = [String]()
        let dependencies = RoomChatSessionSource.LiveDependencies(directory: {
            reads.append("directory"); return transport.directory
        }, transport: {
            reads.append("transport"); return transport
        }, identityLease: { scope in
            reads.append("identity")
            XCTAssertEqual(scope, transport.scope)
            return { valid }
        })
        let session = EnvironmentValues().roomChatSessionSource.makeSession(scope: transport.scope, live: dependencies)
        XCTAssertEqual(reads, ["directory", "transport", "identity"])
        session.setDraft("injected live branch")
        await session.send(authorName: "Me")
        XCTAssertEqual(session.state?.entries.first?.message.text, "injected live branch")
        valid = false
        session.setDraft("late")
        XCTAssertNil(session.state)
    }

    func testTwoLocalOwnersWithIdenticalRoomAndAccountDoNotReuseIdentityOrDraft() {
        let first = RoomChatDemoTransport(chinese: false)
        let second = RoomChatDemoTransport(chinese: false)
        defer { first.close(); second.close() }
        let a = RoomChatSessionSource.local(first)
        let b = RoomChatSessionSource.local(second)
        XCTAssertNotEqual(a.identity, b.identity)
        a.makeSession(scope: first.scope, live: forbiddenLive).setDraft("only first")
        XCTAssertEqual(b.makeSession(scope: second.scope, live: forbiddenLive).state?.draft, "")
    }
}
