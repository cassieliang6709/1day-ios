import Foundation
import CloudKit

/// Backend for shared rooms, on CloudKit's public database.
///
/// Design:
/// - `Room` record: recordName IS the 6-char join code, so joining is a direct
///   fetch (no query, no index needed).
/// - `Clip` record: recordName is deterministic (`code_author_dayN`) so a
///   re-record overwrites the same record. Video travels as a CKAsset.
///
/// Public DB requires the device be signed into iCloud (checked up front).
enum CloudKitService {
    static let containerID = "iCloud.com.cassie.AISetlog"
    private static var db: CKDatabase {
        CKContainer(identifier: containerID).publicCloudDatabase
    }

    enum CKServiceError: LocalizedError {
        case notSignedIntoiCloud
        case roomNotFound
        case fieldNotQueryable

        var errorDescription: String? {
            switch self {
            case .notSignedIntoiCloud:
                return "Sign into iCloud (Settings ▸ your name) to record with friends."
            case .roomNotFound:
                return "No room with that code. Double-check it with your friend."
            case .fieldNotQueryable:
                return "Room isn't set up yet — the CloudKit index is still deploying."
            }
        }
    }

    // MARK: - Account

    static func ensureAccountAvailable() async throws {
        let status = try await CKContainer(identifier: containerID).accountStatus()
        guard status == .available else { throw CKServiceError.notSignedIntoiCloud }
    }

    // MARK: - Rooms

    /// Unambiguous alphabet (no O/0/I/1) for a friendly, dictatable code.
    private static let codeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    private static func makeCode() -> String {
        String((0..<6).map { _ in codeAlphabet.randomElement()! })
    }

    struct RemoteRoom {
        let code: String
        let title: String
        let startDate: Date
        let ownerID: String
        let ownerName: String
        let mode: Challenge.Mode
        let clipLength: Challenge.ClipLength
        let templateName: String?
        let momentTitles: [String]?
    }

    static func createRoom(
        title: String,
        ownerID: String,
        ownerName: String,
        mode: Challenge.Mode = .sevenDay,
        clipLength: Challenge.ClipLength = .tiny,
        templateName: String? = nil,
        momentTitles: [String]? = nil
    ) async throws -> RemoteRoom {
        try await ensureAccountAvailable()
        // Retry on the astronomically unlikely code collision.
        for _ in 0..<5 {
            let code = makeCode()
            let record = CKRecord(recordType: "Room", recordID: .init(recordName: code))
            record["title"] = title as CKRecordValue
            record["startDate"] = Date.now as CKRecordValue
            record["ownerID"] = ownerID as CKRecordValue
            record["ownerName"] = ownerName as CKRecordValue
            record["mode"] = mode.rawValue as CKRecordValue
            record["clipLength"] = clipLength.rawValue as CKRecordValue
            if let templateName { record["templateName"] = templateName as CKRecordValue }
            if let momentTitles { record["momentTitles"] = momentTitles.joined(separator: "\n") as CKRecordValue }
            do {
                let saved = try await db.save(record)
                return room(from: saved)
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue // code taken, try another
            }
        }
        throw CKError(.limitExceeded)
    }

    static func fetchRoom(code: String) async throws -> RemoteRoom {
        try await ensureAccountAvailable()
        do {
            let record = try await db.record(for: .init(recordName: code))
            return room(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            throw CKServiceError.roomNotFound
        }
    }

    private static func room(from r: CKRecord) -> RemoteRoom {
        RemoteRoom(
            code: r.recordID.recordName,
            title: r["title"] as? String ?? "Challenge",
            startDate: r["startDate"] as? Date ?? .now,
            ownerID: r["ownerID"] as? String ?? "",
            ownerName: r["ownerName"] as? String ?? "Friend",
            mode: Challenge.Mode(rawValue: r["mode"] as? String ?? "") ?? .sevenDay,
            clipLength: Challenge.ClipLength(rawValue: r["clipLength"] as? String ?? "") ?? .tiny,
            templateName: r["templateName"] as? String,
            momentTitles: (r["momentTitles"] as? String)?
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init))
    }

    // MARK: - Clips

    struct RemoteClip: Identifiable {
        let id: String          // recordName
        let day: Int
        let authorID: String
        let authorName: String
        let recordedAt: Date
        let localURL: URL       // downloaded asset, cached on disk
        let overlayText: String?
    }

    private static func clipRecordName(code: String, authorID: String, day: Int) -> String {
        "\(code)_\(authorID)_day\(day)"
    }

    /// Upload (or overwrite) my clip for a given day.
    static func uploadClip(
        code: String,
        day: Int,
        authorID: String,
        authorName: String,
        fileURL: URL,
        overlayText: String? = nil
    ) async throws {
        try await ensureAccountAvailable()
        let id = CKRecord.ID(recordName: clipRecordName(code: code, authorID: authorID, day: day))
        // Fetch-and-update if it exists so a re-record replaces the same record.
        let record: CKRecord
        if let existing = try? await db.record(for: id) {
            record = existing
        } else {
            record = CKRecord(recordType: "Clip", recordID: id)
        }
        record["roomCode"] = code as CKRecordValue
        record["day"] = day as CKRecordValue
        record["authorID"] = authorID as CKRecordValue
        record["authorName"] = authorName as CKRecordValue
        record["recordedAt"] = Date.now as CKRecordValue
        record["video"] = CKAsset(fileURL: fileURL)
        if let overlayText, !overlayText.isEmpty {
            record["overlayText"] = overlayText as CKRecordValue
        } else {
            record["overlayText"] = nil
        }
        _ = try await db.save(record)
    }

    /// All clips in a room, downloaded to a local cache directory.
    static func fetchClips(code: String, into cacheDir: URL) async throws -> [RemoteClip] {
        try await ensureAccountAvailable()
        let query = CKQuery(
            recordType: "Clip",
            predicate: NSPredicate(format: "roomCode == %@", code))
        query.sortDescriptors = [NSSortDescriptor(key: "day", ascending: true)]

        let matched: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            (matched, _) = try await db.records(matching: query)
        } catch let error as CKError where error.code == .invalidArguments {
            // Field not marked queryable yet (schema still deploying).
            throw CKServiceError.fieldNotQueryable
        }

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        var clips: [RemoteClip] = []
        for (_, result) in matched {
            guard let record = try? result.get(),
                  let asset = record["video"] as? CKAsset,
                  let assetURL = asset.fileURL else { continue }
            let dest = cacheDir.appendingPathComponent("\(record.recordID.recordName).mov")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: assetURL, to: dest)
            } catch { continue }
            clips.append(RemoteClip(
                id: record.recordID.recordName,
                day: record["day"] as? Int ?? 0,
                authorID: record["authorID"] as? String ?? "",
                authorName: record["authorName"] as? String ?? "Friend",
                recordedAt: record["recordedAt"] as? Date ?? .now,
                localURL: dest,
                overlayText: record["overlayText"] as? String))
        }
        return clips
    }
}
