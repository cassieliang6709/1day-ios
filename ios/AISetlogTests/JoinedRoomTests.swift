import CloudKit
import XCTest
@testable import AISetlog

/// Two people signing in as themselves and landing in the same room — the
/// first thing that has to be right before anything else about sharing
/// matters. Runs against the real CloudKit development database and skips
/// itself when iCloud isn't available.
@MainActor
final class JoinedRoomTests: XCTestCase {
    private var createdCode: String?
    private var hostAccount: AccountStore!
    private var guestAccount: AccountStore!

    override func setUp() async throws {
        try await super.setUp()
        do {
            try await CloudKitService.ensureAccountAvailable()
        } catch {
            throw XCTSkip("Needs a simulator or device signed into iCloud: \(error)")
        }
        hostAccount = AccountStore()
        hostAccount.signInAsTester(named: "Host Phone")
        guestAccount = AccountStore()
        guestAccount.signInAsTester(named: "Guest Phone")
    }

    override func tearDown() async throws {
        if let code = createdCode {
            for account in [hostAccount, guestAccount] {
                guard let id = account?.account?.id else { continue }
                try? await CloudKitService.deleteMyRoomData(
                    authorID: id,
                    clips: (1...3).map { (code: code, day: $0) },
                    reactions: [], commentIDs: [], roomCodes: [code])
            }
        }
        UserDefaults.standard.removeObject(forKey: "account.v1")
        try await super.tearDown()
    }

    private func store(for account: AccountStore) -> ChallengeStore {
        let store = ChallengeStore(repository: MemoryRepository())
        store.account = account
        return store
    }

    func testSigningInGivesEachDeviceItsOwnIdentity() throws {
        let host = try XCTUnwrap(hostAccount.account)
        let guest = try XCTUnwrap(guestAccount.account)

        XCTAssertTrue(hostAccount.isSignedIn)
        XCTAssertNotEqual(host.id, guest.id, "two testers must not share an author id")
        XCTAssertEqual(host.displayName, "Host Phone")

        hostAccount.signOut()
        XCTAssertFalse(hostAccount.isSignedIn)
    }

    func testGuestJoiningByCodeMirrorsTheHostsRoom() async throws {
        let hostStore = store(for: hostAccount)
        let room = try await hostStore.createSharedRoom(
            title: "Join test", mode: .oneDay,
            momentTitles: ["Wake up", "Coffee", "Night"])
        createdCode = room.roomCode

        let guestStore = store(for: guestAccount)
        let joined = try await guestStore.joinRoom(code: try XCTUnwrap(room.roomCode))

        XCTAssertEqual(joined.title, "Join test")
        XCTAssertEqual(joined.roomCode, room.roomCode)
        XCTAssertEqual(joined.ownerName, "Host Phone")
        XCTAssertEqual(joined.momentTitles, ["Wake up", "Coffee", "Night"])
        XCTAssertEqual(joined.cards.count, 3, "the guest gets the host's moment list")
        XCTAssertTrue(joined.isShared)

        // Joining twice is the same room, not a duplicate.
        let again = try await guestStore.joinRoom(code: try XCTUnwrap(room.roomCode))
        XCTAssertEqual(again.id, joined.id)
        XCTAssertEqual(guestStore.challenges.filter { $0.roomCode == room.roomCode }.count, 1)
    }

    /// The roster is what tells you you're in the right room with the right
    /// person — before anyone has filmed anything.
    func testTheRosterShowsTheHostBeforeAnyoneHasFilmed() async throws {
        let hostStore = store(for: hostAccount)
        let room = try await hostStore.createSharedRoom(title: "Roster test")
        createdCode = room.roomCode

        let guestStore = store(for: guestAccount)
        let joined = try await guestStore.joinRoom(code: try XCTUnwrap(room.roomCode))

        let names = guestStore.members(for: joined.id).map(\.name)
        XCTAssertTrue(names.contains("Guest Phone"), "I should see myself: \(names)")
        XCTAssertTrue(names.contains("Host Phone"), "I should see the host: \(names)")
    }
}

private final class MemoryRepository: ChallengeRepository {
    private var challenges: [Challenge] = []
    private var templates: [ChallengeTemplate] = []
    func loadChallenges() -> [Challenge] { challenges }
    func saveChallenges(_ challenges: [Challenge]) { self.challenges = challenges }
    func loadTemplates() -> [ChallengeTemplate] { templates }
    func saveTemplates(_ templates: [ChallengeTemplate]) { self.templates = templates }
}
