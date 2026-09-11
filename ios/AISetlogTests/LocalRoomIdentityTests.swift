import XCTest
@testable import AISetlog

@MainActor
final class LocalRoomIdentityTests: XCTestCase {
    func testMemoryIdentityRenameAndSignOutNeverInvalidateLiveLease() {
        let epoch = AccountStore.identityRevision
        let first = AccountStore(localIdentity: .init(id: "demo-a", displayName: "A"))
        let second = AccountStore(localIdentity: .init(id: "demo-b", displayName: "B"))
        first.rename(to: "  Local A  ")
        XCTAssertEqual(first.account?.displayName, "Local A")
        XCTAssertEqual(second.account?.displayName, "B")
        first.signOut()
        XCTAssertFalse(first.isSignedIn)
        XCTAssertTrue(second.isSignedIn)
        XCTAssertEqual(AccountStore.identityRevision, epoch)
    }

    func testLivePersistencePathSurvivesReloadAndKeepsEpochSemantics() throws {
        // Same initializer/path as the app, redirected to a disposable suite.
        let suite = "1day.identity-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let live = AccountStore(defaults: defaults)
        XCTAssertFalse(live.isSignedIn)
        let before = AccountStore.identityRevision
        live.signInAsTester(named: "Live")
        XCTAssertEqual(AccountStore.identityRevision, before &+ 1)
        let id = live.account?.id
        live.rename(to: "Renamed")
        XCTAssertEqual(AccountStore.identityRevision, before &+ 1)
        let reloaded = AccountStore(defaults: defaults)
        XCTAssertEqual(reloaded.account?.id, id)
        XCTAssertEqual(reloaded.account?.displayName, "Renamed")
        live.signOut()
        XCTAssertEqual(AccountStore.identityRevision, before &+ 2)
        XCTAssertFalse(AccountStore(defaults: defaults).isSignedIn)
    }

    func testMemoryIdentityCannotOverwritePersistedIdentity() throws {
        let suite = "1day.identity-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let live = AccountStore(defaults: defaults)
        live.signInAsTester(named: "Persisted")
        let snapshot = defaults.data(forKey: "account.v1")
        let epoch = AccountStore.identityRevision
        let demo = AccountStore(localIdentity: .init(id: "local-only", displayName: "Sample"))
        demo.rename(to: "Changed")
        demo.signOut()
        XCTAssertEqual(defaults.data(forKey: "account.v1"), snapshot)
        XCTAssertEqual(AccountStore.identityRevision, epoch)
        XCTAssertEqual(live.account?.displayName, "Persisted")
        live.signOut()
    }
}
