import XCTest
@testable import AISetlog

/// The name a room shows next to your clips. Apple hands one over exactly
/// once, so this field is the only way most people will ever change it.
final class AccountNameTests: XCTestCase {
    func testAName() {
        XCTAssertEqual(AccountStore.normalized("Cassie"), "Cassie")
        XCTAssertEqual(AccountStore.normalized("  Cassie  "), "Cassie")
    }

    /// A cleared box is a slip, not a request to be anonymous — and a member
    /// chip with nothing in it is worse than yesterday's name.
    func testAnEmptyFieldIsNotAName() {
        XCTAssertNil(AccountStore.normalized(""))
        XCTAssertNil(AccountStore.normalized("   \n "))
    }

    func testItStopsBeingANameAtSomePoint() {
        let essay = String(repeating: "名", count: AccountStore.nameLimit + 20)
        XCTAssertEqual(
            AccountStore.normalized(essay)?.count, AccountStore.nameLimit)
    }

    // MARK: - rename

    @MainActor
    private func signedIn(as name: String) -> AccountStore {
        let store = AccountStore()
        store.signInAsTester(named: name)
        return store
    }

    @MainActor
    func testRenamingSticksAndSurvivesAReload() {
        let store = signedIn(as: "Old")
        store.rename(to: "  New  ")

        XCTAssertEqual(store.account?.displayName, "New")
        XCTAssertEqual(
            AccountStore().account?.displayName, "New",
            "a name that doesn't survive the next launch was never saved")

        store.signOut()
    }

    /// A cleared field is a slip. Renaming to nothing has to leave the old name
    /// alone rather than blank out what a room shows for you.
    @MainActor
    func testRenamingToNothingChangesNothing() {
        let store = signedIn(as: "Cassie")
        store.rename(to: "   ")

        XCTAssertEqual(store.account?.displayName, "Cassie")

        store.signOut()
    }

    /// Nobody to rename. This has to be a quiet no-op, not a half-made account.
    @MainActor
    func testRenamingWhileSignedOutDoesNotInventAnAccount() {
        let store = AccountStore()
        store.signOut()
        store.rename(to: "Nobody")

        XCTAssertNil(store.account)
        XCTAssertFalse(store.isSignedIn)
    }
}
