#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import Foundation

/// Storage for a future formal-room preview session. Never reads UserDefaults,
/// Documents/clips, production cover files, or legacy migrations.
/// This is only the disk boundary: networking and notifications must separately
/// be disabled before a ChallengeStore using it is exposed in the UI.
final class LocalRoomDemoStorage: ChallengeRepository, ClipFileStore {
    let root: URL
    private(set) var isClosed = false
    private var challenges: [Challenge] = []

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("1day-local-room-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func loadChallenges() -> [Challenge] { challenges }
    func saveChallenges(_ value: [Challenge]) { if !isClosed { challenges = value } }

    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? {
        guard !isClosed else { return nil }
        let name = "day\(day)-\(UUID().uuidString).\(tempURL.pathExtension)"
        let destination = clipURL(fileName: name, challengeID: challengeID)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: tempURL, to: destination)
            return name
        } catch { return nil }
    }

    /// Every name here is already unique and nothing is ever replaced, so a
    /// second take is just another clip.
    func storeExtraTake(from tempURL: URL, day: Int, takeID: UUID, challengeID: UUID) -> String? {
        storeClip(from: tempURL, day: day, challengeID: challengeID)
    }

    func clipURL(fileName: String, challengeID: UUID) -> URL {
        // AVFoundation needs a recognizable media extension on some decoding
        // paths. Encode the entire untrusted name, then append only a whitelisted
        // extension; traversal input still cannot become a path component.
        let ext = (fileName as NSString).pathExtension.lowercased()
        let suffix = ["mov", "mp4", "m4v"].contains(ext) ? "." + ext : ""
        return root.appendingPathComponent(challengeID.uuidString, isDirectory: true)
            .appendingPathComponent(safeComponent(fileName) + suffix)
    }

    func deleteClips(challengeID: UUID) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(challengeID.uuidString))
    }

    func remoteCacheDir(roomCode: String) -> URL {
        root.appendingPathComponent("remote", isDirectory: true)
            .appendingPathComponent(safeComponent(roomCode), isDirectory: true)
    }

    func deleteRemoteCache(roomCode: String) {
        try? FileManager.default.removeItem(at: remoteCacheDir(roomCode: roomCode))
    }

    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {
        // Deliberately never touches production legacy files.
    }

    func close() {
        isClosed = true
        challenges = []
        try? FileManager.default.removeItem(at: root)
    }

    private func safeComponent(_ text: String) -> String {
        // Encode arbitrary input rather than allow ".." or absolute path parts.
        text.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
