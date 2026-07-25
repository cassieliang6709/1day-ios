import Foundation

/// Disk boundary for clip video files. Knows the directory layout under
/// Documents/clips/; the store asks for URLs and copies, never touches
/// FileManager itself.
protocol ClipFileStore {
    /// Copy a freshly recorded clip into permanent storage, replacing any
    /// previous clip for that day (re-recording may switch container formats).
    /// Returns the stored file name, or nil if the copy failed.
    @discardableResult
    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String?
    func clipURL(fileName: String, challengeID: UUID) -> URL
    func deleteClips(challengeID: UUID)
    /// Where downloaded remote (friends') clips for a room are cached.
    func remoteCacheDir(roomCode: String) -> URL
    func deleteRemoteCache(roomCode: String)
    /// Move v1's loose clips/ files into a migrated challenge's directory.
    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID)
}

final class DiskClipFileStore: ClipFileStore {
    private var clipsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clips", isDirectory: true)
    }

    private func clipsDirectory(for id: UUID) -> URL {
        clipsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    @discardableResult
    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? {
        let dir = clipsDirectory(for: challengeID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for ext in ["mov", "mp4"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("day\(day).\(ext)"))
        }
        let dest = dir.appendingPathComponent("day\(day).\(tempURL.pathExtension)")
        do {
            try FileManager.default.copyItem(at: tempURL, to: dest)
            return dest.lastPathComponent
        } catch {
            return nil
        }
    }

    func clipURL(fileName: String, challengeID: UUID) -> URL {
        clipsDirectory(for: challengeID).appendingPathComponent(fileName)
    }

    func deleteClips(challengeID: UUID) {
        try? FileManager.default.removeItem(at: clipsDirectory(for: challengeID))
    }

    func remoteCacheDir(roomCode: String) -> URL {
        clipsRoot.appendingPathComponent("room_\(roomCode)", isDirectory: true)
    }

    func deleteRemoteCache(roomCode: String) {
        try? FileManager.default.removeItem(at: remoteCacheDir(roomCode: roomCode))
    }

    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {
        let newDir = clipsDirectory(for: challengeID)
        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        for name in fileNames {
            let oldURL = clipsRoot.appendingPathComponent(name)
            try? FileManager.default.moveItem(
                at: oldURL, to: newDir.appendingPathComponent(name))
        }
    }
}
