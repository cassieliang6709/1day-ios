import Foundation

/// 拍一拍: one nudge per friend per day, remembered on this device so the
/// grey tile can show it was sent. The poke's record name carries the same
/// day, so a second send from another install still lands on one record.
struct PokeLimiter {
    static let defaultsKey = "rooms.pokes.sent"

    var defaults: UserDefaults = .standard
    var calendar: Calendar = .current

    static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Keyed by who sent it too: a poke the last person signed in here sent
    /// is not one the next person has used up.
    private func key(code: String, targetAuthorID: String) -> String {
        "\(AccountStore.persistedUserID ?? "")|\(code)|\(targetAuthorID)"
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

    /// Gives back a poke that never reached the room.
    func release(code: String, targetAuthorID: String) {
        var all = sent
        all[key(code: code, targetAuthorID: targetAuthorID)] = nil
        sent = all
    }
}

extension CloudKitService {
    static func pokeRecordName(code: String, authorID: String, targetAuthorID: String, dayStamp: String) -> String {
        "\(code)_poke_\(authorID)_\(targetAuthorID)_\(dayStamp)"
    }

    /// One poke row per sender, target and day. The Worker pushes it to the
    /// target only; a second send today lands on the same row.
    static func sendPoke(code: String, authorID: String, authorName: String, targetAuthorID: String) async throws {
        struct Body: Encodable { let roomCode: String; let authorName: String; let targetAuthorID: String }
        let id = pokeRecordName(
            code: code, authorID: authorID, targetAuthorID: targetAuthorID,
            dayStamp: PokeLimiter.dayStamp(.now))
        do {
            try await OneDayAPI.shared.send("PUT", ["pokes", id], json: Body(
                roomCode: code, authorName: authorName, targetAuthorID: targetAuthorID))
        } catch {
            throw serviceError(from: error, fallback: .networkUnavailable)
        }
    }
}
