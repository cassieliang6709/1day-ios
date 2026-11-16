import Foundation

enum RoomClipCache {
    static let manifestFileName = "manifest.json"

    struct Manifest: Codable, Equatable {
        var versions: [String: String] = [:]
    }

    struct RemoteEntry: Equatable {
        let recordName: String
        let version: String?
    }

    struct Plan: Equatable {
        var download: [String]
        var reuse: [String]
        var remove: [String]
    }

    static func fileURL(recordName: String, in dir: URL) -> URL {
        dir.appendingPathComponent("\(recordName).mov")
    }

    static func videoVersion(recordedAt: Date?, changeTag: String?) -> String? {
        if let recordedAt { return "t:\(recordedAt.timeIntervalSince1970)" }
        if let changeTag { return "tag:\(changeTag)" }
        return nil
    }

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
