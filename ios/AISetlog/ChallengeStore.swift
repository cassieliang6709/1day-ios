import Foundation
import Observation

@Observable
final class ChallengeStore {
    private static let defaultsKey = "challenges.v2"
    private static let legacyKey = "challenge.v1"
    private static let templatesKey = "customTemplates.v1"

    var challenges: [Challenge] = [] {
        didSet { persist() }
    }

    var customTemplates: [ChallengeTemplate] = [] {
        didSet { persistTemplates() }
    }

    /// Set once at app launch so shared rooms can attribute + upload clips.
    var account: AccountStore?

    /// Clips fetched from CloudKit per room code (all members). Transient.
    private(set) var remoteClips: [String: [CloudKitService.RemoteClip]] = [:]
    /// Room codes currently being synced (drives a spinner in the board).
    private(set) var syncing: Set<String> = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Challenge].self, from: data) {
            challenges = saved
        } else {
            migrateLegacyIfNeeded()
        }
        if let data = UserDefaults.standard.data(forKey: Self.templatesKey),
           let saved = try? JSONDecoder().decode([ChallengeTemplate].self, from: data) {
            customTemplates = saved
        }
    }

    func challenge(_ id: UUID) -> Challenge? {
        challenges.first { $0.id == id }
    }

    func addCustomTemplate(_ template: ChallengeTemplate) {
        customTemplates.append(template)
    }

    func deleteCustomTemplate(_ template: ChallengeTemplate) {
        customTemplates.removeAll { $0.id == template.id }
    }

    @discardableResult
    func create(
        title: String,
        mode: Challenge.Mode = .sevenDay,
        clipLength: Challenge.ClipLength = .tiny,
        templateName: String? = nil,
        momentTitles: [String]? = nil
    ) -> Challenge {
        let challenge = Challenge(
            id: UUID(),
            title: title,
            startDate: .now,
            cards: (1...cardCount(for: momentTitles)).map { DayCard(day: $0) },
            mode: mode,
            clipLength: clipLength,
            templateName: templateName,
            momentTitles: momentTitles
        )
        challenges.insert(challenge, at: 0)
        return challenge
    }

    // MARK: - Shared rooms (CloudKit)

    enum RoomError: LocalizedError {
        case notSignedIn
        var errorDescription: String? { "Sign in with Apple first to record with friends." }
    }

    /// Create a CloudKit-backed room and mirror it locally.
    @MainActor
    @discardableResult
    func createSharedRoom(
        title: String,
        mode: Challenge.Mode = .sevenDay,
        clipLength: Challenge.ClipLength = .tiny,
        templateName: String? = nil,
        momentTitles: [String]? = nil
    ) async throws -> Challenge {
        guard let me = account?.account else { throw RoomError.notSignedIn }
        let room = try await CloudKitService.createRoom(
            title: title, ownerID: me.id, ownerName: me.displayName,
            mode: mode, clipLength: clipLength,
            templateName: templateName, momentTitles: momentTitles)
        let challenge = Challenge(
            id: UUID(), title: room.title, startDate: room.startDate,
            cards: (1...cardCount(for: room.momentTitles)).map { DayCard(day: $0) },
            mode: room.mode, clipLength: room.clipLength,
            templateName: room.templateName,
            momentTitles: room.momentTitles,
            roomCode: room.code, ownerName: room.ownerName)
        challenges.insert(challenge, at: 0)
        return challenge
    }

    /// Join an existing room by its code, mirroring it locally.
    @MainActor
    @discardableResult
    func joinRoom(code: String) async throws -> Challenge {
        guard account?.account != nil else { throw RoomError.notSignedIn }
        let normalized = code.uppercased().trimmingCharacters(in: .whitespaces)
        // Already joined? Jump to it.
        if let existing = challenges.first(where: { $0.roomCode == normalized }) {
            return existing
        }
        let room = try await CloudKitService.fetchRoom(code: normalized)
        let challenge = Challenge(
            id: UUID(), title: room.title, startDate: room.startDate,
            cards: (1...cardCount(for: room.momentTitles)).map { DayCard(day: $0) },
            mode: room.mode, clipLength: room.clipLength,
            templateName: room.templateName,
            momentTitles: room.momentTitles,
            roomCode: room.code, ownerName: room.ownerName)
        challenges.insert(challenge, at: 0)
        await syncRoom(challenge.id)
        return challenge
    }

    /// Pull every member's clips for a room into the local cache.
    @MainActor
    func syncRoom(_ id: UUID) async {
        guard let challenge = challenge(id), let code = challenge.roomCode else { return }
        syncing.insert(code)
        defer { syncing.remove(code) }
        do {
            let clips = try await CloudKitService.fetchClips(
                code: code, into: remoteCacheDir(for: code))
            remoteClips[code] = clips
        } catch {
            print("[room] sync failed: \(error)")
        }
    }

    /// Members seen in a room: owner + everyone who has uploaded a clip + me.
    func members(for challengeID: UUID) -> [(id: String, name: String)] {
        guard let challenge = challenge(challengeID), let code = challenge.roomCode else { return [] }
        var seen: [String: String] = [:]
        for clip in remoteClips[code] ?? [] { seen[clip.authorID] = clip.authorName }
        if let me = account?.account { seen[me.id] = me.displayName }
        return seen.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: clipsDirectory(for: id))
        if let code = challenge(id)?.roomCode {
            // Leaves the room locally; the shared record stays for others.
            try? FileManager.default.removeItem(at: remoteCacheDir(for: code))
            remoteClips[code] = nil
        }
        challenges.removeAll { $0.id == id }
    }

    /// Moves a freshly recorded clip into permanent storage and marks the card done.
    func saveClip(
        from tempURL: URL,
        day: Int,
        challengeID: UUID,
        overlayText: String? = nil
    ) {
        guard let ci = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        let dir = clipsDirectory(for: challengeID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Re-recording may switch container formats (demo .mp4 vs camera .mov)
        for ext in ["mov", "mp4"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("day\(day).\(ext)"))
        }
        let dest = dir.appendingPathComponent("day\(day).\(tempURL.pathExtension)")
        do {
            try FileManager.default.copyItem(at: tempURL, to: dest)
        } catch {
            return
        }
        guard let idx = challenges[ci].cards.firstIndex(where: { $0.day == day }) else { return }
        challenges[ci].cards[idx].clipFileName = dest.lastPathComponent
        challenges[ci].cards[idx].recordedAt = .now
        challenges[ci].cards[idx].overlayText = overlayText

        // Shared room: also push this clip to CloudKit for friends to see.
        if let code = challenges[ci].roomCode, let me = account?.account {
            let challengeID = challenges[ci].id
            Task { @MainActor in
                do {
                    try await CloudKitService.uploadClip(
                        code: code, day: day, authorID: me.id,
                        authorName: me.displayName, fileURL: dest,
                        overlayText: overlayText)
                    await syncRoom(challengeID)
                } catch {
                    print("[room] upload failed: \(error)")
                }
            }
        }
    }

    func clipURL(for card: DayCard, in challengeID: UUID) -> URL? {
        guard let name = card.clipFileName else { return nil }
        return clipsDirectory(for: challengeID).appendingPathComponent(name)
    }

    /// All recorded clips in day order — the stitcher's input. For a shared
    /// room this merges every member's clips (falling back to my local clips
    /// if the room hasn't been synced yet).
    func recordedClips(for challengeID: UUID) -> [DayClip] {
        guard let challenge = challenge(challengeID) else { return [] }
        if let code = challenge.roomCode, let remote = remoteClips[code], !remote.isEmpty {
            return remote
                .sorted { ($0.day, $0.authorName) < ($1.day, $1.authorName) }
                .map {
                    DayClip(
                        day: $0.day, url: $0.localURL, authorName: $0.authorName,
                        label: challenge.title(forSlot: $0.day),
                        overlayText: $0.overlayText,
                        recordedAt: $0.recordedAt,
                        key: $0.id)
                }
        }
        return challenge.cards.compactMap { card in
            clipURL(for: card, in: challengeID).map {
                DayClip(
                    day: card.day,
                    url: $0,
                    label: challenge.title(forSlot: card.day),
                    overlayText: card.overlayText,
                    recordedAt: card.recordedAt)
            }
        }
    }

    /// Card count for a new challenge: matches a custom moment list's length,
    /// falling back to the original 7-day/7-moment shape.
    private func cardCount(for momentTitles: [String]?) -> Int {
        guard let count = momentTitles?.count, count > 0 else { return 7 }
        return count
    }

    #if DEBUG
    /// Simulator helper: fill every card with the bundled demo clips (only 7 exist)
    /// so the stitching flow can be tested without a camera or waiting 7 days.
    func fillWithDemoClips(challengeID: UUID) {
        let dayCount = challenge(challengeID)?.cards.count ?? 7
        for day in 1...min(dayCount, 7) {
            if let demo = Bundle.main.url(forResource: "day\(day)", withExtension: "mp4") {
                saveClip(
                    from: demo,
                    day: day,
                    challengeID: challengeID,
                    overlayText: day == 1 ? "first little proof" : nil)
            }
        }
    }
    #endif

    // MARK: - Storage

    private var clipsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clips", isDirectory: true)
    }

    private func clipsDirectory(for id: UUID) -> URL {
        clipsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Where downloaded remote (friends') clips for a room are cached.
    private func remoteCacheDir(for code: String) -> URL {
        clipsRoot.appendingPathComponent("room_\(code)", isDirectory: true)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(challenges) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func persistTemplates() {
        if let data = try? JSONEncoder().encode(customTemplates) {
            UserDefaults.standard.set(data, forKey: Self.templatesKey)
        }
    }

    /// v1 stored a single challenge without an id, clips directly in clips/.
    private func migrateLegacyIfNeeded() {
        struct LegacyChallenge: Codable {
            var title: String
            var startDate: Date
            var cards: [DayCard]
        }
        guard let data = UserDefaults.standard.data(forKey: Self.legacyKey),
              let old = try? JSONDecoder().decode(LegacyChallenge.self, from: data)
        else { return }

        let migrated = Challenge(
            id: UUID(), title: old.title, startDate: old.startDate, cards: old.cards)
        let newDir = clipsDirectory(for: migrated.id)
        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        for card in old.cards {
            guard let name = card.clipFileName else { continue }
            let oldURL = clipsRoot.appendingPathComponent(name)
            try? FileManager.default.moveItem(
                at: oldURL, to: newDir.appendingPathComponent(name))
        }
        challenges = [migrated]
        UserDefaults.standard.removeObject(forKey: Self.legacyKey)
    }
}
