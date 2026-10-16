import CloudKit
import Foundation

/// 拍一拍: one nudge per friend per day, remembered on this device so the
/// grey tile can show it was sent. The CloudKit record name carries the same
/// day, so a second send from another install still lands on one record.
struct PokeLimiter {
    static let defaultsKey = "rooms.pokes.sent"

    var defaults: UserDefaults = .standard
    var calendar: Calendar = .current

    static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func key(code: String, targetAuthorID: String) -> String {
        "\(code)|\(targetAuthorID)"
    }

    private var sent: [String: String] {
        get { defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }

    func hasPoked(code: String, targetAuthorID: String, on date: Date = .now) -> Bool {
        sent[key(code: code, targetAuthorID: targetAuthorID)] == Self.dayStamp(date, calendar: calendar)
    }

    /// Records the poke and returns true, or returns false when this person
    /// was already poked today.
    func claim(code: String, targetAuthorID: String, on date: Date = .now) -> Bool {
        guard !hasPoked(code: code, targetAuthorID: targetAuthorID, on: date) else { return false }
        var all = sent
        all[key(code: code, targetAuthorID: targetAuthorID)] = Self.dayStamp(date, calendar: calendar)
        sent = all
        return true
    }
}

extension CloudKitService {
    static func pokeRecordName(code: String, authorID: String, targetAuthorID: String, dayStamp: String) -> String {
        "\(code)_poke_\(authorID)_\(targetAuthorID)_\(dayStamp)"
    }

    /// Writes one `Poke` record in the room. The recipient's query
    /// subscription on `Poke` turns it into a local notification.
    static func sendPoke(code: String, authorID: String, authorName: String, targetAuthorID: String) async throws {
        try await ensureAccountAvailable()
        let id = CKRecord.ID(recordName: pokeRecordName(
            code: code, authorID: authorID, targetAuthorID: targetAuthorID,
            dayStamp: PokeLimiter.dayStamp(.now)))
        let record = CKRecord(recordType: "Poke", recordID: id)
        record["roomCode"] = code as CKRecordValue
        record["day"] = 1 as CKRecordValue
        record["authorID"] = authorID as CKRecordValue
        record["authorName"] = authorName as CKRecordValue
        record["targetAuthorID"] = targetAuthorID as CKRecordValue
        record["createdAt"] = Date.now as CKRecordValue
        // Same `.allKeys` upsert as the reaction path: a second send today
        // rewrites the one record instead of failing as a duplicate insert.
        let (saved, _) = try await CKContainer(identifier: containerID).publicCloudDatabase
            .modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        for (_, result) in saved { _ = try result.get() }
    }
}
