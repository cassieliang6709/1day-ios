import Foundation
import Observation
import UIKit

/// The five moods the 我的 tab offers. Raw values are what goes to disk and to
/// CloudKit, so never rename them.
enum Mood: String, Codable, CaseIterable, Identifiable {
    case happy, calm, tired, sad, angry

    var id: String { rawValue }

    /// Asset catalog name of the mascot face for this mood (`MoodHappy`, …).
    var imageName: String {
        switch self {
        case .happy: return "MoodHappy"
        case .calm: return "MoodCalm"
        case .tired: return "MoodTired"
        case .sad: return "MoodSad"
        case .angry: return "MoodAngry"
        }
    }

    var label: String {
        switch self {
        case .happy: return Strings.moodHappy
        case .calm: return Strings.moodCalm
        case .tired: return Strings.moodTired
        case .sad: return Strings.moodSad
        case .angry: return Strings.moodAngry
        }
    }
}

/// One day's mood. `day` is the local calendar day as `yyyy-MM-dd`, which is
/// also the key everywhere (store, file, CloudKit record name).
struct MoodEntry: Codable, Equatable {
    var day: String
    var mood: Mood
    var note: String
    var updatedAt: Date
}

enum MoodDay {
    /// `yyyy-MM-dd` in the device's current calendar day.
    static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// What the store needs from the cloud. `nil` in tests and previews, so they
/// never touch CloudKit.
/// One line in the 和小方块聊两句 sheet. Local only: never synced, never sent
/// anywhere except back to the chat endpoint as context.
struct MascotChatMessage: Codable, Equatable, Identifiable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    var role: Role
    var content: String
}

protocol MoodSyncing {
    /// Overwrite these entries remotely.
    func push(_ entries: [MoodEntry]) async throws
    /// Every entry changed remotely since the last successful fetch.
    func fetchChanges() async throws -> [MoodEntry]
    /// False when there's no iCloud account; the store then stays local.
    func isAvailable() async -> Bool
}

/// Today's mood plus a one-line note, one entry per day.
///
/// Local JSON is the source of truth for the UI; CloudKit (private database)
/// is a backup that other devices merge from, last write wins by `updatedAt`.
@MainActor
@Observable
final class MoodStore {
    private(set) var entries: [String: MoodEntry] = [:]
    /// Days changed locally that the cloud hasn't confirmed yet.
    private var pending: Set<String> = []

    /// Per-day chat with the mascot, `yyyy-MM-dd` → messages. Lives in a
    /// sibling file so it can never ride along with the CloudKit snapshot.
    private(set) var chats: [String: [MascotChatMessage]] = [:]

    /// A day's conversation stops here; the sheet then says goodnight.
    static let chatLimit = 10
    /// Older days are dropped on save. Nobody scrolls back to last month's chat.
    static let chatDaysKept = 14

    private let fileURL: URL?
    private let sync: MoodSyncing?
    private let now: () -> Date
    private var isSyncing = false
    private var needsAnotherPass = false
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?

    private struct Snapshot: Codable {
        var entries: [MoodEntry]
        var pending: [String]
    }

    init(fileURL: URL? = MoodStore.defaultFileURL,
         sync: MoodSyncing? = MoodStore.defaultSync,
         now: @escaping () -> Date = { .now }) {
        self.fileURL = fileURL
        self.sync = sync
        self.now = now
        load()
        loadChats()
        guard sync != nil else { return }
        // Fetch on launch, and again whenever the app comes back to the front.
        Task { await syncNow() }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
    }

    // MARK: Reading

    /// The entry for the calendar day containing `date`, if one was set.
    func mood(on date: Date) -> MoodEntry? {
        entries[MoodDay.key(for: date)]
    }

    var today: MoodEntry? { mood(on: now()) }

    // MARK: Writing

    /// Set (or change) today's mood. Keeps whatever note was already there.
    func setMood(_ mood: Mood, on date: Date? = nil) {
        let key = MoodDay.key(for: date ?? now())
        let note = entries[key]?.note ?? ""
        write(MoodEntry(day: key, mood: mood, note: note, updatedAt: now()))
    }

    /// Change the note on a day that already has a mood. A note without a
    /// mood isn't an entry, so this does nothing until a face is picked.
    func setNote(_ note: String, on date: Date? = nil) {
        let key = MoodDay.key(for: date ?? now())
        guard var entry = entries[key] else { return }
        let trimmed = String(note.prefix(120))
        guard entry.note != trimmed else { return }
        entry.note = trimmed
        entry.updatedAt = now()
        write(entry)
    }

    private func write(_ entry: MoodEntry) {
        entries[entry.day] = entry
        pending.insert(entry.day)
        save()
        Task { await syncNow() }
    }

    // MARK: Mascot chat (local only)

    func chat(on date: Date? = nil) -> [MascotChatMessage] {
        chats[MoodDay.key(for: date ?? now())] ?? []
    }

    /// Room for one more user line *and* the reply to it.
    func canSendChat(on date: Date? = nil) -> Bool {
        chat(on: date).count <= Self.chatLimit - 2
    }

    /// Appends one line to the day's chat. Ignored once the day is full, for
    /// empty text, or before a mood exists (there's nothing to chat about).
    @discardableResult
    func appendChat(_ role: MascotChatMessage.Role, _ content: String, on date: Date? = nil) -> Bool {
        let key = MoodDay.key(for: date ?? now())
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entries[key] != nil, !text.isEmpty else { return false }
        var day = chats[key] ?? []
        guard day.count < Self.chatLimit else { return false }
        day.append(MascotChatMessage(role: role, content: String(text.prefix(300))))
        chats[key] = day
        saveChats()
        return true
    }

    // MARK: Sync

    /// Push what's pending, then merge in remote changes. Safe to call often:
    /// launch, foreground, every edit. Failures leave `pending` as it was so
    /// the next call retries.
    func syncNow() async {
        guard let sync else { return }
        // An edit during a pass gets picked up by one more pass, not dropped.
        guard !isSyncing else { needsAnotherPass = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            needsAnotherPass = false
            await syncPass(sync)
        } while needsAnotherPass
    }

    private func syncPass(_ sync: MoodSyncing) async {
        guard await sync.isAvailable() else { return }

        let outgoing = pending.compactMap { entries[$0] }
        if !outgoing.isEmpty {
            do {
                try await sync.push(outgoing)
                // Only clear what we sent and that hasn't changed since.
                for sent in outgoing where entries[sent.day] == sent {
                    pending.remove(sent.day)
                }
                save()
            } catch {
                print("[mood] push failed: \(error)")
            }
        }

        do {
            merge(try await sync.fetchChanges())
        } catch {
            print("[mood] fetch failed: \(error)")
        }
    }

    /// Last write wins. A remote entry replaces ours only if it's newer.
    func merge(_ remote: [MoodEntry]) {
        var changed = false
        for entry in remote {
            if let local = entries[entry.day], local.updatedAt >= entry.updatedAt { continue }
            entries[entry.day] = entry
            pending.remove(entry.day)
            changed = true
        }
        if changed { save() }
    }

    // MARK: Disk

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        entries = Dictionary(snapshot.entries.map { ($0.day, $0) }, uniquingKeysWith: { a, b in
            a.updatedAt >= b.updatedAt ? a : b
        })
        pending = Set(snapshot.pending)
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = Snapshot(
            entries: entries.values.sorted { $0.day < $1.day },
            pending: pending.sorted())
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            print("[mood] save failed: \(error)")
        }
    }

    private var chatFileURL: URL? {
        fileURL?.deletingLastPathComponent().appendingPathComponent("mascot-chat.json")
    }

    private func loadChats() {
        guard let chatFileURL, let data = try? Data(contentsOf: chatFileURL),
              let decoded = try? JSONDecoder().decode([String: [MascotChatMessage]].self, from: data)
        else { return }
        chats = decoded
    }

    private func saveChats() {
        guard let chatFileURL else { return }
        let keep = Set(chats.keys.sorted().suffix(Self.chatDaysKept))
        chats = chats.filter { keep.contains($0.key) }
        do {
            try FileManager.default.createDirectory(
                at: chatFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(chats).write(to: chatFileURL, options: .atomic)
        } catch {
            print("[mood] chat save failed: \(error)")
        }
    }

    // MARK: Defaults

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Moods", isDirectory: true)
            .appendingPathComponent("moods.json")
    }

    /// Live CloudKit sync, except under XCTest and SwiftUI previews.
    nonisolated static var defaultSync: MoodSyncing? {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return nil }
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return nil }
        return MoodSync()
    }
}
