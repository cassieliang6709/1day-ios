import Foundation
import Observation
import UIKit

enum Mood: String, Codable, CaseIterable, Identifiable {
    case happy, calm, tired, sad, angry

    var id: String { rawValue }

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

struct MoodEntry: Codable, Equatable {
    var day: String
    var mood: Mood
    var note: String
    var updatedAt: Date
}

enum MoodDay {
    static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

protocol MoodSyncing {
    func push(_ entries: [MoodEntry]) async throws
    func fetchChanges() async throws -> [MoodEntry]
    func isAvailable() async -> Bool
    func wantsFullUpload() -> Bool
    func didFullUpload()
}

extension MoodSyncing {
    func wantsFullUpload() -> Bool { false }
    func didFullUpload() {}
}

@MainActor
@Observable
final class MoodStore {
    private(set) var entries: [String: MoodEntry] = [:]
    private var pending: Set<String> = []

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
        removeLegacyMascotChat()
        guard sync != nil else { return }
        Task { await syncNow() }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
    }


    func mood(on date: Date) -> MoodEntry? {
        entries[MoodDay.key(for: date)]
    }

    var today: MoodEntry? { mood(on: now()) }


    func setMood(_ mood: Mood, on date: Date? = nil) {
        let key = MoodDay.key(for: date ?? now())
        let note = entries[key]?.note ?? ""
        write(MoodEntry(day: key, mood: mood, note: note, updatedAt: now()))
    }

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


    func syncNow() async {
        guard let sync else { return }
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

        let full = sync.wantsFullUpload()
        let outgoing = full ? Array(entries.values) : pending.compactMap { entries[$0] }
        if full && outgoing.isEmpty { sync.didFullUpload() }
        if !outgoing.isEmpty {
            do {
                try await sync.push(outgoing)
                if full { sync.didFullUpload() }
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

    private func removeLegacyMascotChat() {
        guard let url = fileURL?.deletingLastPathComponent()
            .appendingPathComponent("mascot-chat.json") else { return }
        try? FileManager.default.removeItem(at: url)
        UserDefaults.standard.removeObject(forKey: "mascotName")
        UserDefaults.standard.removeObject(forKey: "mascotNameAsked")
    }


    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Moods", isDirectory: true)
            .appendingPathComponent("moods.json")
    }

    nonisolated static var defaultSync: MoodSyncing? {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return nil }
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return nil }
        return MoodSync()
    }
}
