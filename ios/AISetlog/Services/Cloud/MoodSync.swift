import Foundation

struct MoodSync: MoodSyncing {
    private static let cursorKey = "moodSync.cursor.v2"

    var api: OneDayAPI = .shared
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, api: OneDayAPI = .shared) {
        self.defaults = defaults
        self.api = api
    }


    struct Row: Codable, Equatable {
        let day: String
        let mood: String
        let note: String
        let updatedAt: Int64
    }

    static func row(for entry: MoodEntry) -> Row {
        Row(day: entry.day, mood: entry.mood.rawValue, note: entry.note, updatedAt: entry.updatedAt.apiMillis)
    }

    static func entry(from row: Row) -> MoodEntry? {
        guard let mood = Mood(rawValue: row.mood) else { return nil }
        return MoodEntry(day: row.day, mood: mood, note: row.note, updatedAt: Date(apiMillis: row.updatedAt))
    }


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
