import Foundation

/// What a room's remote-clip cache directory already holds, and which clips a
/// sync therefore has to download again.
///
/// A room sync used to pull every member's video on every pass — every ten
/// seconds while the room page was open — and copy each one over the file it
/// already had. The query now comes back without the videos; this decides,
/// from a small manifest kept next to the files, which records are new or
/// changed and so need their video fetched. Everything here is plain file and
/// dictionary work, so the rule can be checked without CloudKit.
enum RoomClipCache {
    static let manifestFileName = "manifest.json"

    /// recordName → the video version that record had when its file was
    /// written. A record is reused only while its version still matches.
    struct Manifest: Codable, Equatable {
        var versions: [String: String] = [:]
    }

    /// One remote record as the metadata-only query saw it. A nil version
    /// means the record can't say which take it holds, so it is always
    /// downloaded rather than trusted.
    struct RemoteEntry: Equatable {
        let recordName: String
        let version: String?
    }

    struct Plan: Equatable {
        /// Records whose video has to be fetched, in the order the room listed them.
        var download: [String]
        /// Records whose cached file is still the current take.
        var reuse: [String]
        /// Cached files whose record is no longer in the room.
        var remove: [String]
    }

    static func fileURL(recordName: String, in dir: URL) -> URL {
        dir.appendingPathComponent("\(recordName).mov")
    }

    /// The version a clip's video is at.
    ///
    /// `recordedAt` rather than the record's change tag, because only
    /// `CloudKitService.uploadClip` writes the video and it always stamps
    /// `recordedAt` with it, while a caption edit rewrites the record (new
    /// change tag) and leaves the take alone — keying on the tag would
    /// download the same video again for three changed words. Records without
    /// `recordedAt` fall back to the change tag.
    static func videoVersion(recordedAt: Date?, changeTag: String?) -> String? {
        if let recordedAt { return "t:\(recordedAt.timeIntervalSince1970)" }
        if let changeTag { return "tag:\(changeTag)" }
        return nil
    }

    /// Decide what to download, keep, and delete.
    ///
    /// `cachedFiles` is what is actually on disk: a manifest entry whose file
    /// went missing is not a reason to skip the download.
    static func plan(
        remote: [RemoteEntry], manifest: Manifest, cachedFiles: Set<String>
    ) -> Plan {
        var plan = Plan(download: [], reuse: [], remove: [])
        for entry in remote {
            if let version = entry.version,
               manifest.versions[entry.recordName] == version,
               cachedFiles.contains(entry.recordName) {
                plan.reuse.append(entry.recordName)
            } else {
                plan.download.append(entry.recordName)
            }
        }
        let remoteNames = Set(remote.map(\.recordName))
        plan.remove = cachedFiles.subtracting(remoteNames).sorted()
        return plan
    }

    /// The manifest to write once the downloads are done.
    ///
    /// A download that failed keeps whatever entry it had before, so the old
    /// file (still on disk) stays described and the next sync, seeing the
    /// version still differs, tries again. Records that left the room drop out.
    static func manifest(
        after plan: Plan, remote: [RemoteEntry], downloaded: Set<String>,
        previous: Manifest
    ) -> Manifest {
        let remoteNames = Set(remote.map(\.recordName))
        var next = Manifest(versions: previous.versions.filter { remoteNames.contains($0.key) })
        let current = Set(plan.reuse).union(downloaded)
        for entry in remote where current.contains(entry.recordName) {
            next.versions[entry.recordName] = entry.version
        }
        return next
    }

    // MARK: - Disk

    /// A missing or unreadable manifest reads as empty: the worst that does is
    /// one full download, which is what every sync used to cost.
    static func loadManifest(in dir: URL) -> Manifest {
        let url = dir.appendingPathComponent(manifestFileName)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return Manifest() }
        return manifest
    }

    static func saveManifest(_ manifest: Manifest, in dir: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: dir.appendingPathComponent(manifestFileName), options: .atomic)
    }

    /// Record names that have a cached video in the directory.
    static func cachedRecordNames(in dir: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return Set(names.compactMap { name in
            guard name.hasSuffix(".mov") else { return nil }
            return String(name.dropLast(".mov".count))
        })
    }

    static func removeFiles(_ recordNames: [String], in dir: URL) {
        for name in recordNames {
            try? FileManager.default.removeItem(at: fileURL(recordName: name, in: dir))
        }
    }

    /// Put a freshly downloaded video in place of the cached one.
    ///
    /// Copied beside the destination first, so a copy that fails part-way
    /// leaves the previous file where it was instead of nothing.
    static func install(_ source: URL, recordName: String, in dir: URL) throws {
        try install(source, to: fileURL(recordName: recordName, in: dir))
    }

    /// Stage beside the destination and atomically replace it. Readers keep
    /// the previous complete file until the replacement is ready.
    static func install(_ source: URL, to dest: URL, consumingSource: Bool = false) throws {
        let fm = FileManager.default
        let partial = dest.appendingPathExtension("\(UUID().uuidString).part")
        defer { try? fm.removeItem(at: partial) }
        if consumingSource {
            try fm.moveItem(at: source, to: partial)
        } else {
            try fm.copyItem(at: source, to: partial)
        }
        if fm.fileExists(atPath: dest.path) {
            _ = try fm.replaceItemAt(dest, withItemAt: partial)
        } else {
            try fm.moveItem(at: partial, to: dest)
        }
    }
}
