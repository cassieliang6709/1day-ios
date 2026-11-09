#if DEBUG
import Foundation

/// Debug-only: a real shared room, made in one tap.
///
/// It used to also write two fake friends' clips straight into CloudKit. The
/// Worker only lets a session write as itself, so that part is gone: the room
/// is real and empty, and a second phone (or `DebugFakeFriends`, which pastes
/// clips into the local copy only) fills it.
///
/// Settings has the button; `-debugCreateTestRoom YES` runs it once at launch.
@MainActor
enum DebugTestRoom {
    static let launchFlag = "debugCreateTestRoom"
    /// Set by the launch flag; consumed the first time it is read.
    private static var launchConsumed = false

    static func consumeLaunchRequest() -> Bool {
        guard !launchConsumed, UserDefaults.standard.bool(forKey: launchFlag) else { return false }
        launchConsumed = true
        return true
    }

    /// Creates the room and syncs it. Throws
    /// `ChallengeStore.RoomError.notSignedIn` when nobody is signed in.
    @discardableResult
    static func create(in store: ChallengeStore) async throws -> Challenge {
        guard store.account?.isSignedIn == true else { throw ChallengeStore.RoomError.notSignedIn }
        let challenge = try await store.createSharedRoom(title: Strings.debugTestRoomTitle)
        await store.syncRoom(challenge.id)
        print("[debug-room] created test room code=\(challenge.roomCode ?? "-")")
        return challenge
    }
}
#endif
