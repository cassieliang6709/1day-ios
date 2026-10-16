import Foundation
import CloudKit

/// 心情日记 backup, on the user's **private** CloudKit database. Only the
/// owner can read it; nothing here ever reaches a room or a friend.
///
/// Design:
/// - `MoodEntry` record, recordName `mood-yyyy-MM-dd`: one per day, a
///   re-save overwrites it (`.allKeys`, same reason as
///   `CloudKitService.upsert`). Last write wins by `updatedAt`, decided by
///   `MoodStore.merge`.
/// - Records live in a custom zone (`Moods`) rather than the default zone so
///   fetching is a zone-changes read with a change token. A query would need
///   a queryable index deployed in the CloudKit Console first — the same trap
///   behind `CKServiceError.fieldNotQueryable` for rooms.
/// - No iCloud account → `isAvailable` is false and the store stays local.
struct MoodSync: MoodSyncing {
    static let recordType = "MoodEntry"
    static let zoneID = CKRecordZone.ID(zoneName: "Moods", ownerName: CKCurrentUserDefaultName)

    private static let tokenKey = "moodSync.changeToken.v1"
    private static let zoneReadyKey = "moodSync.zoneReady.v1"

    private var container: CKContainer { CKContainer(identifier: CloudKitService.containerID) }
    private var db: CKDatabase { container.privateCloudDatabase }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Record mapping

    static func recordID(forDay day: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "mood-\(day)", zoneID: zoneID)
    }

    static func record(for entry: MoodEntry) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID(forDay: entry.day))
        record["day"] = entry.day as CKRecordValue
        record["mood"] = entry.mood.rawValue as CKRecordValue
        record["note"] = entry.note as CKRecordValue
        record["updatedAt"] = entry.updatedAt as CKRecordValue
        return record
    }

    /// `nil` for a record this build can't read (unknown mood from a newer
    /// version, missing fields) — skipped rather than crashing the merge.
    static func entry(from record: CKRecord) -> MoodEntry? {
        guard record.recordType == recordType,
              let day = record["day"] as? String,
              let raw = record["mood"] as? String, let mood = Mood(rawValue: raw),
              let updatedAt = record["updatedAt"] as? Date
        else { return nil }
        return MoodEntry(day: day, mood: mood,
                         note: record["note"] as? String ?? "", updatedAt: updatedAt)
    }

    // MARK: MoodSyncing

    func isAvailable() async -> Bool {
        do {
            return try await container.accountStatus() == .available
        } catch {
            print("[mood] iCloud account status failed: \(error)")
            return false
        }
    }

    func push(_ entries: [MoodEntry]) async throws {
        guard !entries.isEmpty else { return }
        try await ensureZone()
        do {
            try await save(entries)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // Zone was removed (e.g. the user cleared iCloud data): recreate once.
            resetZoneState()
            try await ensureZone()
            try await save(entries)
        } catch let error as CKError {
            throw CloudKitService.serviceError(from: error, fallback: .networkUnavailable)
        }
    }

    func fetchChanges() async throws -> [MoodEntry] {
        try await ensureZone()
        var token = loadToken()
        var result: [MoodEntry] = []
        do {
            // Guard against a token that never stops saying "more coming".
            for _ in 0..<50 {
                let changes = try await db.recordZoneChanges(inZoneWith: Self.zoneID, since: token)
                for (_, modification) in changes.modificationResultsByID {
                    if let record = try? modification.get().record,
                       let entry = Self.entry(from: record) {
                        result.append(entry)
                    }
                }
                token = changes.changeToken
                guard changes.moreComing else { break }
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            // Start over from scratch next time.
            defaults.removeObject(forKey: Self.tokenKey)
            return []
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            resetZoneState()
            return []
        } catch let error as CKError {
            throw CloudKitService.serviceError(from: error, fallback: .networkUnavailable)
        }
        saveToken(token)
        return result
    }

    // MARK: Helpers

    private func save(_ entries: [MoodEntry]) async throws {
        let (saved, _) = try await db.modifyRecords(
            saving: entries.map(Self.record(for:)), deleting: [], savePolicy: .allKeys)
        for (_, result) in saved { _ = try result.get() }
    }

    private func ensureZone() async throws {
        guard !defaults.bool(forKey: Self.zoneReadyKey) else { return }
        do {
            let (saved, _) = try await db.modifyRecordZones(
                saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
            for (_, result) in saved { _ = try result.get() }
            defaults.set(true, forKey: Self.zoneReadyKey)
        } catch let error as CKError {
            throw CloudKitService.serviceError(from: error, fallback: .networkUnavailable)
        }
    }

    private func resetZoneState() {
        defaults.removeObject(forKey: Self.zoneReadyKey)
        defaults.removeObject(forKey: Self.tokenKey)
    }

    private func loadToken() -> CKServerChangeToken? {
        guard let data = defaults.data(forKey: Self.tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(_ token: CKServerChangeToken?) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else { return }
        defaults.set(data, forKey: Self.tokenKey)
    }
}
