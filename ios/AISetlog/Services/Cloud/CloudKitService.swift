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

    /// Every record matching a query, following CloudKit's cursor.
    ///
    /// One `records(matching:)` returns a single page — 100 records in
    /// practice — plus a cursor for the rest. Reading only the first page
    /// silently drops everything past it, which for a room that has been going
    /// a while means most of its comments just aren't there.
    private static func allRecords(matching query: CKQuery) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var response = try await db.records(matching: query)
        // A guard against a cursor that never clears; 50 pages is far past any
        // room we expect and still terminates.
        for _ in 0..<50 {
            records.append(contentsOf: response.matchResults.compactMap { try? $0.1.get() })
            guard let cursor = response.queryCursor else { break }
            response = try await db.records(continuingMatchFrom: cursor)
        }
        return records
    }

    /// Save a record whose name we chose ourselves, overwriting anything
    /// already there.
    ///
    /// `db.save` on a freshly built `CKRecord` fails with "record to insert
    /// already exists" when the name is taken, and every deterministic name
    /// here is taken the second time around — a retry, a double tap, or a
    /// second device replaying the same write. `.allKeys` ignores the change
    /// tag, which is what "writing this again is harmless" has to mean.
    private static func upsert(_ record: CKRecord) async throws {
        let (saved, _) = try await db.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys)
        for (_, result) in saved { _ = try result.get() }
    }

    enum CKServiceError: LocalizedError {
        case notSignedIntoiCloud
        case roomNotFound
        case fieldNotQueryable

        var errorDescription: String? {
            switch self {
            case .notSignedIntoiCloud:
                return Strings.errorICloud
            case .roomNotFound:
                return Strings.errorNoRoom
            case .fieldNotQueryable:
                return Strings.errorIndexDeploying
            }
        }
    }

    // MARK: - Account

    static func ensureAccountAvailable() async throws {
        let status = try await CKContainer(identifier: containerID).accountStatus()
        guard status == .available else { throw CKServiceError.notSignedIntoiCloud }
    }

    // MARK: - Rooms

    struct RemoteRoom {
        let code: String
        let title: String
        let startDate: Date
        let ownerID: String
        let ownerName: String
        let mode: Challenge.Mode
        let clipLength: Challenge.ClipLength
        let orientation: Challenge.Orientation
        let templateName: String?
        let momentTitles: [String]?
    }

    static func createRoom(
        title: String,
        ownerID: String,
        ownerName: String,
        mode: Challenge.Mode = .sevenDay,
        clipLength: Challenge.ClipLength = .tiny,
        orientation: Challenge.Orientation = .portrait,
        templateName: String? = nil,
        momentTitles: [String]? = nil
    ) async throws -> RemoteRoom {
        try await ensureAccountAvailable()
        // Retry on the astronomically unlikely code collision.
        for _ in 0..<5 {
            let code = InviteCode.make()
            let record = CKRecord(recordType: "Room", recordID: .init(recordName: code))
            record["title"] = title as CKRecordValue
            record["startDate"] = Date.now as CKRecordValue
            record["ownerID"] = ownerID as CKRecordValue
            record["ownerName"] = ownerName as CKRecordValue
            record["mode"] = mode.rawValue as CKRecordValue
            record["clipLength"] = clipLength.rawValue as CKRecordValue
            record["orientation"] = orientation.rawValue as CKRecordValue
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
            orientation: Challenge.Orientation(rawValue: r["orientation"] as? String ?? "") ?? .portrait,
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

    /// Internal rather than private so the naming rule can be checked without a
    /// network: "writing this again is harmless" is only true while the same
    /// clip keeps deriving the same name, and that is a property of this
    /// string, not of CloudKit.
    static func clipRecordName(code: String, authorID: String, day: Int) -> String {
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

        let matched: [CKRecord]
        do {
            matched = try await allRecords(matching: query)
        } catch let error as CKError where error.code == .invalidArguments {
            // Field not marked queryable yet (schema still deploying).
            throw CKServiceError.fieldNotQueryable
        }

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        var clips: [RemoteClip] = []
        for record in matched {
            guard let asset = record["video"] as? CKAsset,
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

    // MARK: - Reactions & comments (append-only, no merge conflicts)

    struct RemoteReaction {
        let day: Int
        let emoji: String
        let authorID: String
        let authorName: String
        let targetAuthorID: String
        let createdAt: Date
    }

    struct RemoteComment {
        let id: String          // recordName == the local ClipComment UUID
        let day: Int
        let text: String
        let authorID: String
        let authorName: String
        let targetAuthorID: String
        let createdAt: Date
    }

    /// Deterministic name so re-adding the same emoji is idempotent and a
    /// toggle-off deletes exactly the same record — never a read-modify-write.
    /// Internal for the same reason as ``clipRecordName(code:authorID:day:)``.
    static func reactionRecordName(code: String, targetAuthorID: String, authorID: String, day: Int, emoji: String) -> String {
        "\(code)_\(targetAuthorID)_day\(day)_\(authorID)_\(emoji.unicodeScalars.map { String($0.value) }.joined(separator: "-"))"
    }

    /// Add (on) or remove (off) one emoji from a day's clip for one author.
    static func setReaction(
        code: String, day: Int, authorID: String, authorName: String, targetAuthorID: String,
        emoji: String, on: Bool
    ) async throws {
        try await ensureAccountAvailable()
        let id = CKRecord.ID(recordName: reactionRecordName(
            code: code, targetAuthorID: targetAuthorID, authorID: authorID, day: day, emoji: emoji))
        if on {
            let record = CKRecord(recordType: "Reaction", recordID: id)
            record["roomCode"] = code as CKRecordValue
            record["day"] = day as CKRecordValue
            record["emoji"] = emoji as CKRecordValue
            record["authorID"] = authorID as CKRecordValue
            record["authorName"] = authorName as CKRecordValue
            record["targetAuthorID"] = targetAuthorID as CKRecordValue
            record["createdAt"] = Date.now as CKRecordValue
            try await upsert(record)
        } else {
            do {
                try await db.deleteRecord(withID: id)
            } catch let error as CKError where error.code == .unknownItem {
                // Already gone — nothing to do.
            }
        }
    }

    /// Post a comment. `id` is the local ClipComment UUID so both sides dedupe.
    static func postComment(
        code: String, day: Int, id: String,
        text: String, authorID: String, authorName: String, targetAuthorID: String
    ) async throws {
        try await ensureAccountAvailable()
        let record = CKRecord(recordType: "Comment", recordID: .init(recordName: id))
        record["roomCode"] = code as CKRecordValue
        record["day"] = day as CKRecordValue
        record["text"] = text as CKRecordValue
        record["authorID"] = authorID as CKRecordValue
        record["authorName"] = authorName as CKRecordValue
        record["targetAuthorID"] = targetAuthorID as CKRecordValue
        record["createdAt"] = Date.now as CKRecordValue
        try await upsert(record)
    }

    static func deleteComment(id: String) async throws {
        try await ensureAccountAvailable()
        do {
            try await db.deleteRecord(withID: .init(recordName: id))
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone.
        }
    }

    // MARK: - Account deletion

    /// Erases everything this person put in a shared room.
    ///
    /// Deletion works from record IDs the app can reconstruct rather than from
    /// queries: clip and reaction record names are deterministic, and comment
    /// records use the local comment UUID. A query-based sweep would depend on
    /// `authorID` being a queryable index in the production schema, and would
    /// silently delete nothing if it isn't — the wrong failure mode for
    /// something a user asked for explicitly.
    ///
    /// Rooms the person created are kept but stripped of their name: the room
    /// holds other people's clips too, and destroying a friend's story is not
    /// what "delete my account" should mean.
    static func deleteMyRoomData(
        authorID: String,
        clips: [(code: String, day: Int)],
        reactions: [(code: String, targetAuthorID: String, day: Int, emoji: String)],
        commentIDs: [String],
        roomCodes: [String]
    ) async throws {
        try await ensureAccountAvailable()

        var ids: [CKRecord.ID] = []
        for clip in clips {
            ids.append(.init(recordName: clipRecordName(
                code: clip.code, authorID: authorID, day: clip.day)))
        }
        for reaction in reactions {
            ids.append(.init(recordName: reactionRecordName(
                code: reaction.code, targetAuthorID: reaction.targetAuthorID,
                authorID: authorID, day: reaction.day, emoji: reaction.emoji)))
        }
        ids.append(contentsOf: commentIDs.map { CKRecord.ID(recordName: $0) })

        // Chunked: CloudKit rejects oversized batches, and one bad ID
        // shouldn't abort the rest of someone's deletion.
        for chunk in stride(from: 0, to: ids.count, by: 200).map({
            Array(ids[$0..<min($0 + 200, ids.count)])
        }) {
            _ = try? await db.modifyRecords(saving: [], deleting: chunk)
        }

        for code in roomCodes {
            guard let room = try? await db.record(for: .init(recordName: code)),
                  room["ownerID"] as? String == authorID
            else { continue }
            room["ownerName"] = Strings.deletedMemberName as CKRecordValue
            _ = try? await db.save(room)
        }
    }

    /// Fetch all reactions + comments in a room. Returns empties (never throws
    /// for a missing index) so the caller degrades cleanly to local-only.
    static func fetchInteractions(code: String) async throws -> (reactions: [RemoteReaction], comments: [RemoteComment]) {
        try await ensureAccountAvailable()
        async let reactions = fetchReactions(code: code)
        async let comments = fetchComments(code: code)
        return (try await reactions, try await comments)
    }

    private static func fetchReactions(code: String) async throws -> [RemoteReaction] {
        let query = CKQuery(recordType: "Reaction", predicate: NSPredicate(format: "roomCode == %@", code))
        let matched: [CKRecord]
        do {
            matched = try await allRecords(matching: query)
        } catch let error as CKError where error.code == .invalidArguments || error.code == .unknownItem {
            return [] // type/index not deployed yet — degrade to local-only
        }
        return matched.compactMap { r in
            guard let emoji = r["emoji"] as? String else { return nil }
            return RemoteReaction(
                day: r["day"] as? Int ?? 0, emoji: emoji,
                authorID: r["authorID"] as? String ?? "",
                authorName: r["authorName"] as? String ?? "Friend",
                targetAuthorID: r["targetAuthorID"] as? String ?? "",
                createdAt: r["createdAt"] as? Date ?? .now)
        }
    }

    private static func fetchComments(code: String) async throws -> [RemoteComment] {
        let query = CKQuery(recordType: "Comment", predicate: NSPredicate(format: "roomCode == %@", code))
        let matched: [CKRecord]
        do {
            matched = try await allRecords(matching: query)
        } catch let error as CKError where error.code == .invalidArguments || error.code == .unknownItem {
            return []
        }
        return matched.compactMap { r in
            guard let text = r["text"] as? String else { return nil }
            return RemoteComment(
                id: r.recordID.recordName,
                day: r["day"] as? Int ?? 0, text: text,
                authorID: r["authorID"] as? String ?? "",
                authorName: r["authorName"] as? String ?? "Friend",
                targetAuthorID: r["targetAuthorID"] as? String ?? "",
                createdAt: r["createdAt"] as? Date ?? .now)
        }
    }
}
