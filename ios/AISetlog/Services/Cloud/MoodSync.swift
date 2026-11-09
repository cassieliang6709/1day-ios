import Foundation

/// 心情日记 backup on the Worker (`/moods`). Only the owner can read it;
/// nothing here ever reaches a room or a friend.
///
/// - One row per day; a re-save overwrites it. Last write wins by
///   `updatedAt`, decided by `MoodStore.merge` here and by the Worker there.
/// - Fetching reads "everything after the last `seq` I saw" — the cursor is
///   kept per signed-in person, so the next one to sign in on this phone
///   starts from the beginning of their own diary.
/// - The first sync for a person sends every entry on the phone once: what
///   went to CloudKit before never counted as pending.
/// - Not signed in → `isAvailable` is false and the store stays local.
struct MoodSync: MoodSyncing {
    private static let cursorKey = "moodSync.cursor.v2"

    var api: OneDayAPI = .shared
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, api: OneDayAPI = .shared) {
        self.defaults = defaults
        self.api = api
    }

    // MARK: Wire mapping

    struct Row: Codable, Equatable {
        let day: String
        let mood: String
        let note: String
        let updatedAt: Int64
    }

    static func row(for entry: MoodEntry) -> Row {
        Row(day: entry.day, mood: entry.mood.rawValue, note: entry.note, updatedAt: entry.updatedAt.apiMillis)
    }

    /// `nil` for a row this build can't read (a mood from a newer version) —
    /// skipped rather than failing the merge.
    static func entry(from row: Row) -> MoodEntry? {
        guard let mood = Mood(rawValue: row.mood) else { return nil }
        return MoodEntry(day: row.day, mood: mood, note: row.note, updatedAt: Date(apiMillis: row.updatedAt))
    }

    // MARK: MoodSyncing

    func isAvailable() async -> Bool {
        api.isSignedIn
    }

    func push(_ entries: [MoodEntry]) async throws {
        guard !entries.isEmpty else { return }
        struct Body: Encodable { let entries: [Row] }
        for start in stride(from: 0, to: entries.count, by: 500) {
            let chunk = entries[start..<min(start + 500, entries.count)].map(Self.row(for:))
            do {
                try await api.send("PUT", ["moods"], json: Body(entries: chunk))
            } catch {
                throw CloudKitService.serviceError(from: error, fallback: .networkUnavailable)
            }
        }
    }

    func fetchChanges() async throws -> [MoodEntry] {
        struct Page: Decodable { let entries: [Lossy<Row>]; let cursor: Int; let more: Bool }
        let key = cursorDefaultsKey
        var cursor = defaults.integer(forKey: key)
        var result: [MoodEntry] = []
        do {
            // Guard against a cursor that never stops saying "more coming".
            for _ in 0..<50 {
                let page = try await api.get(
                    Page.self, ["moods"], query: [URLQueryItem(name: "after", value: String(cursor))])
                result += page.entries.compactMap { $0.value.flatMap(Self.entry(from:)) }
                cursor = page.cursor
                guard page.more else { break }
            }
        } catch {
            throw CloudKitService.serviceError(from: error, fallback: .networkUnavailable)
        }
        defaults.set(cursor, forKey: key)
        return result
    }

    func wantsFullUpload() -> Bool {
        !defaults.bool(forKey: fullUploadDefaultsKey)
    }

    func didFullUpload() {
        defaults.set(true, forKey: fullUploadDefaultsKey)
    }

    private var fullUploadDefaultsKey: String {
        "moodSync.fullUpload.v1.\(api.keychain.load()?.userId ?? "")"
    }

    private var cursorDefaultsKey: String {
        "\(Self.cursorKey).\(api.keychain.load()?.userId ?? "")"
    }
}
