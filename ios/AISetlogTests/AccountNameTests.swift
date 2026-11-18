import XCTest
import AuthenticationServices
@testable import AISetlog

final class AccountNameTests: XCTestCase {
    func testAName() {
        XCTAssertEqual(AccountStore.normalized("Cassie"), "Cassie")
        XCTAssertEqual(AccountStore.normalized("  Cassie  "), "Cassie")
    }

    func testAnEmptyFieldIsNotAName() {
        XCTAssertNil(AccountStore.normalized(""))
        XCTAssertNil(AccountStore.normalized("   \n "))
    }

    func testItStopsBeingANameAtSomePoint() {
        let essay = String(repeating: "名", count: AccountStore.nameLimit + 20)
        XCTAssertEqual(
            AccountStore.normalized(essay)?.count, AccountStore.nameLimit)
    }


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

    @MainActor
    func testRenamingToNothingChangesNothing() {
        let store = signedIn(as: "Cassie")
        store.rename(to: "   ")

        XCTAssertEqual(store.account?.displayName, "Cassie")

        store.signOut()
    }

    @MainActor
    func testRenamingWhileSignedOutDoesNotInventAnAccount() {
        let store = AccountStore()
        store.signOut()
        store.rename(to: "Nobody")

        XCTAssertNil(store.account)
        XCTAssertFalse(store.isSignedIn)
    }

    func testOnlyARevokedCredentialSignsOut() {
        XCTAssertTrue(AccountStore.signsOut(on: .revoked))
        XCTAssertFalse(AccountStore.signsOut(on: .notFound))
        XCTAssertFalse(AccountStore.signsOut(on: .transferred))
        XCTAssertFalse(AccountStore.signsOut(on: .authorized))
    }
}
