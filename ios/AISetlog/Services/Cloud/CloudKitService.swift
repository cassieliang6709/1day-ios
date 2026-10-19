import Foundation
import CloudKit

/// Backend for shared rooms, on CloudKit's public database.
///
/// Design:
/// - `Room` record: recordName IS the 6-char join code, so joining is a direct
///   fetch (no query, no index needed).
/// - `Clip` record: recordName is deterministic (`code_author_dayN`) for a
///   person's first take of a moment; every later take gets its own record,
///   `code_author_dayN_<takeID>`, so filming again adds instead of overwriting.
///   Video travels as a CKAsset.
/// - `Member` record: recordName is `code_authorID`, written when someone
///   joins by code; joining again rewrites the same record.
///
/// Public DB requires the device be signed into iCloud (checked up front).
enum CloudKitService {
    static let containerID = "iCloud.com.cassie.AISetlog"
    /// Whether this build is signed against CloudKit Production. Mirrors the
    /// `icloud-container-environment` entitlement through Info.plist, since
    /// an app can't read its own entitlements at runtime.
    static var isProduction: Bool {
        Bundle.main.object(forInfoDictionaryKey: "OneDayCloudKitEnvironment") as? String != "Development"
    }
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
        case networkUnavailable
        case roomCreateFailed
        case roomJoinFailed

        var errorDescription: String? {
            switch self {
            case .notSignedIntoiCloud:
                return Strings.errorICloud
            case .roomNotFound:
                return Strings.errorNoRoom
            case .fieldNotQueryable:
                return Strings.errorIndexDeploying
            case .networkUnavailable:
                return Strings.errorNetwork
            case .roomCreateFailed:
                return Strings.errorRoomCreateFailed
            case .roomJoinFailed:
                return Strings.errorRoomJoinFailed
            }
        }
    }

    /// CloudKit's own `localizedDescription` is "未能完成操作。（CKErrorDomain
    /// 错误 4。）" — a domain name and a number, shown to somebody who was
    /// trying to record with a friend. Every path that surfaces a CKError to
    /// the UI maps it here first; `fallback` is what an unrecognised code says
    /// instead of leaking the domain.
    static func serviceError(from error: CKError, fallback: CKServiceError) -> Error {
        switch error.code {
        case .unknownItem:
            return CKServiceError.roomNotFound
        case .notAuthenticated, .managedAccountRestricted:
            return CKServiceError.notSignedIntoiCloud
        case .networkFailure, .networkUnavailable, .serviceUnavailable,
             .requestRateLimited, .zoneBusy:
            return CKServiceError.networkUnavailable
        default:
            return fallback
        }
    }
    static func ensureAccountAvailable() async throws {
        let status = try await CKContainer(identifier: containerID).accountStatus()
        guard status == .available else {
            // Diagnostic (temporary): which state the join/create path died on.
            print("[room] iCloud account not available: status=\(status.rawValue) container=\(containerID)")
            throw CKServiceError.notSignedIntoiCloud
        }
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
        let cameraStyle: CameraStyle?
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
        cameraStyle: CameraStyle? = nil,
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
            if let cameraStyle { record["cameraStyle"] = cameraStyle.rawValue as CKRecordValue }
            if let templateName { record["templateName"] = templateName as CKRecordValue }
            // Diagnostic (temporary): the code under which the room is saved,
            // so a "no room with that code" report can be matched against it.
            print("[room] creating room code=\(code) container=\(containerID)")
            do {
                let saved = try await db.save(record)
                print("[room] created room code=\(code)")
                return room(from: saved)
            } catch let error as CKError where error.code == .serverRecordChanged {
                print("[room] code \(code) taken, retrying")
                continue // code taken, try another
            } catch let error as CKError {
                print("[room] create room code=\(code) failed: \(error)")
                throw serviceError(from: error, fallback: .roomCreateFailed)
            } catch {
                print("[room] create room code=\(code) failed: \(error)")
                throw error
            }
        }
        throw CKServiceError.roomCreateFailed
    }

    static func fetchRoom(code: String) async throws -> RemoteRoom {
        try await ensureAccountAvailable()
        // Diagnostic (temporary): the exact code being fetched, so a
        // cross-device miss can be compared with the creator's save log.
        print("[room] fetching room code=\(code) container=\(containerID)")
        do {
            let record = try await db.record(for: .init(recordName: code))
            print("[room] fetched room code=\(code)")
            return room(from: record)
        } catch let error as CKError {
            // Only `.unknownItem` truly means "no room with that code" — a
            // network drop or a signed-out iCloud account failing the fetch
            // must reach the user as what it is, not as a wrong-code hint.
            print("[room] fetch room code=\(code) failed: \(error)")
            throw serviceError(from: error, fallback: .roomJoinFailed)
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
            cameraStyle: (r["cameraStyle"] as? String).flatMap(CameraStyle.init),
            templateName: r["templateName"] as? String,
            momentTitles: (r["momentTitles"] as? String)?
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init))
    }

    // MARK: - Members

    /// One person's place in a room, written when they join by code.
    ///
    /// Deterministic (`code_authorID`) for the same reason clip names are:
    /// joining again — a second device, a reinstall, a retry — rewrites the
    /// one record instead of adding another, and account deletion can name
    /// it without a query.
    static func memberRecordName(code: String, authorID: String) -> String {
        "\(code)_\(authorID)"
    }

    /// Upsert my `Member` record for a room. `joinedAt` is the latest join:
    /// joining again overwrites it.
    static func saveMember(
        code: String, authorID: String, displayName: String, joinedAt: Date
    ) async throws {
        try await ensureAccountAvailable()
        let record = CKRecord(
            recordType: "Member",
            recordID: .init(recordName: memberRecordName(code: code, authorID: authorID)))
        record["roomCode"] = code as CKRecordValue
        record["userID"] = authorID as CKRecordValue
        record["displayName"] = displayName as CKRecordValue
        record["joinedAt"] = joinedAt as CKRecordValue
        try await upsert(record)
        print("[room] saved member code=\(code)")
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
        /// Where the author put their caption.
        ///
        /// Read-only for now, and nil in practice: a caption edit doesn't sync
        /// at all yet (see `ChallengeStore.updateOverlayText`), so nothing
        /// writes this field. It is read anyway, because the day edits do sync
        /// is the day a friend's placement has to be honoured rather than
        /// silently recentred — and a clip whose sticker string doesn't parse
        /// still shows its words, in the old place.
        /// Defaulted, so a fixture or a test that doesn't care about captions
        /// doesn't have to say so.
        var captionSticker: CaptionSticker? = nil
    }

    /// Internal rather than private so the naming rule can be checked without a
    /// network: "writing this again is harmless" is only true while the same
    /// clip keeps deriving the same name, and that is a property of this
    /// string, not of CloudKit.
    ///
    /// `takeID` nil is take 1, whose name is the one every version has used.
    /// A later take appends its id. An older phone lists a room's clips by
    /// query and reads `day`/`authorID` off the record, never off the name, so
    /// it shows the extra takes too without knowing what they are.
    static func clipRecordName(code: String, authorID: String, day: Int, takeID: UUID? = nil) -> String {
        let first = "\(code)_\(authorID)_day\(day)"
        guard let takeID else { return first }
        return "\(first)_\(takeID.uuidString)"
    }

    /// Which take a clip record holds, read back off its name: nil for take 1
    /// (or a name this app didn't write).
    static func takeID(fromClipRecordName name: String, code: String, authorID: String, day: Int) -> UUID? {
        let prefix = clipRecordName(code: code, authorID: authorID, day: day) + "_"
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }

    /// Upload (or overwrite) my clip for a given day.
    /// Rewrites just the caption on a clip that is already in the room.
    ///
    /// Fetch-and-set rather than a fresh record: the video is a `CKAsset` and
    /// re-uploading it to change three words would cost the friend a download
    /// of the same take. A clip that isn't up yet is not an error — the next
    /// upload carries whatever the caption says by then.
    static func updateClipCaption(
        code: String, day: Int, authorID: String, overlayText: String?, takeID: UUID? = nil
    ) async throws {
        try await ensureAccountAvailable()
        let id = CKRecord.ID(recordName: clipRecordName(
            code: code, authorID: authorID, day: day, takeID: takeID))
        guard let record = try? await db.record(for: id) else { return }
        if let overlayText, !overlayText.isEmpty {
            record["overlayText"] = overlayText as CKRecordValue
        } else {
            record["overlayText"] = nil
        }
        _ = try await db.save(record)
    }

    static func uploadClip(
        code: String,
        day: Int,
        authorID: String,
        authorName: String,
        fileURL: URL,
        overlayText: String? = nil,
        recordedAt: Date,
        takeID: UUID? = nil
    ) async throws {
        try await ensureAccountAvailable()
        let id = CKRecord.ID(recordName: clipRecordName(
            code: code, authorID: authorID, day: day, takeID: takeID))
        // Fetch-and-update if it exists, so a retried upload of the same take
        // lands on the same record. A new take has a new name and never finds
        // one.
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
        // When the take was filmed, not when it reached the room. This used to
        // be `Date.now`, and an upload is not always the moment after the
        // take: a failed one is retried on a later sync, and a draft can sit
        // for an hour before it is filed. Either way friends saw 3:21 on a clip
        // filmed at 2:06 — the time the network came back, not the time of the
        // moment the card is about.
        record["recordedAt"] = recordedAt as CKRecordValue
        record["video"] = CKAsset(fileURL: fileURL)
        if let overlayText, !overlayText.isEmpty {
            record["overlayText"] = overlayText as CKRecordValue
        } else {
            record["overlayText"] = nil
        }
        _ = try await db.save(record)
        // Diagnostic: the success half of `[room] upload failed`, so a clip a
        // friend says they can't see can be matched against what this phone
        // actually put up, and when it says the take was filmed.
        print("[room] uploaded clip code=\(code) day=\(day) recordedAt=\(recordedAt) take=\(takeID?.uuidString ?? "1")")
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
                overlayText: record["overlayText"] as? String,
                captionSticker: (record["captionSticker"] as? String)
                    .flatMap(CaptionSticker.init(cloudValue:))))
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
    /// Deletes a batch and reports back only what CloudKit individually
    /// confirmed gone.
    ///
    /// The difference from `deleteMyRoomData` is the whole point of it: that
    /// one wraps the batch in `try?` and carries on, so a network drop halfway
    /// through looks exactly like success. An account deletion cannot be
    /// allowed to look like that, so this returns the confirmed IDs and lets
    /// the caller's journal decide what still needs another go.
    ///
    /// A record that is already absent counts as confirmed. It is the state the
    /// caller asked for, and a retry after a partial batch will hit this case
    /// for everything the first attempt did manage.
    static func deleteRecordsConfirmingEachOne(_ names: Set<String>) async throws -> Set<String> {
        guard !names.isEmpty else { return [] }
        try await ensureAccountAvailable()

        var confirmed: Set<String> = []
        let ids = names.sorted().map { CKRecord.ID(recordName: $0) }
        // Chunked: CloudKit rejects oversized batches, and one bad ID shouldn't
        // cost us the confirmations for the rest.
        for chunk in stride(from: 0, to: ids.count, by: 200).map({
            Array(ids[$0..<min($0 + 200, ids.count)])
        }) {
            let (_, deleted) = try await db.modifyRecords(saving: [], deleting: chunk)
            for (id, result) in deleted {
                switch result {
                case .success:
                    confirmed.insert(id.recordName)
                case .failure(let error as CKError) where error.code == .unknownItem:
                    confirmed.insert(id.recordName)
                case .failure:
                    continue
                }
            }
        }
        return confirmed
    }

    static func deleteMyRoomData(
        authorID: String,
        clips: [(code: String, day: Int)],
        reactions: [(code: String, targetAuthorID: String, day: Int, emoji: String)],
        commentIDs: [String],
        roomCodes: [String],
        // Records addressed by name rather than rebuilt here: a moment's extra
        // takes (`clipRecordName(…, takeID:)`), and anything else whose name
        // only the caller knows.
        otherRecordNames: [String] = []
    ) async throws {
        try await ensureAccountAvailable()

        var ids: [CKRecord.ID] = otherRecordNames.map { CKRecord.ID(recordName: $0) }
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
