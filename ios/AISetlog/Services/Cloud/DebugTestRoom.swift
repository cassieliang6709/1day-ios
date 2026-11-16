#if DEBUG
import Foundation

@MainActor
enum DebugTestRoom {
    static let launchFlag = "debugCreateTestRoom"
    private static var launchConsumed = false

    static func consumeLaunchRequest() -> Bool {
        guard !launchConsumed, UserDefaults.standard.bool(forKey: launchFlag) else { return false }
        launchConsumed = true
        return true
    }

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
