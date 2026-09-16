import Foundation

/// Room scope is independent of a video's author and moment number.
/// The account is part of the local scope so drafts/outbox never cross logins.
struct RoomChatScope: Codable, Equatable {
    let accountID: String
    let roomCode: String
}

struct RoomChatMessage: Codable, Equatable, Identifiable {
    let id: UUID
    let roomCode: String
    let authorID: String
    let authorName: String
    let text: String
    let createdAt: Date
    /// Context only; never used to filter the room conversation.
    let moment: Int?
}

enum RoomChatDelivery: String, Codable {
    case sending, failed, sent
}

struct RoomChatEntry: Codable, Equatable, Identifiable {
    let message: RoomChatMessage
    var delivery: RoomChatDelivery
    var id: UUID { message.id }
}

/// Pure state machine. Transport errors are not empty snapshots. The caller
/// applies a snapshot only after a successful room-wide fetch, and persists
/// state before treating a queued message as accepted by the composer.
struct RoomChatState: Codable, Equatable {
    enum StateError: Error { case emptyMessage, messageTooLong, wrongRoom, invalidScope, unknownMessage }
    static let maximumMessageLength = 2_000

    let scope: RoomChatScope
    private(set) var entries: [RoomChatEntry] = []
    private(set) var deletedIDs: Set<UUID> = []
    var draft = ""

    private enum CodingKeys: String, CodingKey { case scope, entries, deletedIDs, draft }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scope = try values.decode(RoomChatScope.self, forKey: .scope)
        entries = try values.decode([RoomChatEntry].self, forKey: .entries)
        deletedIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .deletedIDs) ?? []
        draft = try values.decode(String.self, forKey: .draft)
    }

    init(scope: RoomChatScope) throws {
        guard !scope.accountID.isEmpty, scope.accountID != "local", !scope.roomCode.isEmpty else {
            throw StateError.invalidScope
        }
        self.scope = scope
    }

    var orderedEntries: [RoomChatEntry] {
        entries.sorted {
            if $0.message.createdAt != $1.message.createdAt {
                return $0.message.createdAt < $1.message.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    mutating func enqueue(authorName: String, moment: Int? = nil,
                          id: UUID = UUID(), now: Date = Date()) throws -> RoomChatMessage {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StateError.emptyMessage }
        guard text.count <= Self.maximumMessageLength else { throw StateError.messageTooLong }
        guard !deletedIDs.contains(id), !entries.contains(where: { $0.id == id }) else { throw StateError.invalidScope }
        let message = RoomChatMessage(id: id, roomCode: scope.roomCode,
                                      authorID: scope.accountID, authorName: authorName,
                                      text: text, createdAt: now, moment: moment)
        entries.append(RoomChatEntry(message: message, delivery: .sending))
        draft = ""
        return message
    }

    mutating func markFailed(_ id: UUID) {
        // A delayed transport failure cannot demote an already echoed message.
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].delivery == .sending else { return }
        entries[index].delivery = .failed
    }

    mutating func retry(_ id: UUID) throws -> RoomChatMessage {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].message.authorID == scope.accountID,
              entries[index].delivery == .failed else { throw StateError.unknownMessage }
        entries[index].delivery = .sending
        return entries[index].message
    }

    mutating func acknowledge(_ message: RoomChatMessage) throws {
        guard message.roomCode == scope.roomCode else { throw StateError.wrongRoom }
        guard !deletedIDs.contains(message.id) else { return }
        if let index = entries.firstIndex(where: { $0.id == message.id }) {
            entries[index] = RoomChatEntry(message: message, delivery: .sent)
        } else {
            entries.append(RoomChatEntry(message: message, delivery: .sent))
        }
    }

    mutating func mergeSuccessfulFetch(_ messages: [RoomChatMessage]) throws {
        // Validate the whole batch first; a bad response cannot partially mutate state.
        guard messages.allSatisfy({ $0.roomCode == scope.roomCode }) else {
            throw StateError.wrongRoom
        }
        for message in messages { try acknowledge(message) }
        // Keep local entries absent from this fetch. An eventually consistent
        // query may not echo a confirmed write yet. Deletions need explicit
        // tombstones/confirmation, not inference from a missing record.
    }

    /// Only an explicit server deletion/unknownItem confirmation may call this.
    /// Failed or in-flight local sends are never removed by a missing remote record.
    mutating func confirmDeleted(_ ids: Set<UUID>) {
        let confirmed = Set(entries.filter { ids.contains($0.id) && $0.delivery == .sent }.map(\.id))
        deletedIDs.formUnion(confirmed)
        entries.removeAll { confirmed.contains($0.id) }
    }

    /// Replan against current state rather than applying a potentially stale plan.
    /// This never sends messages or removes the source legacy comments.
    @discardableResult
    mutating func recoverLegacyComments(_ candidates: [LegacyRoomChatMigration.Candidate]) -> LegacyRoomChatMigration.Plan {
        let plan = LegacyRoomChatMigration.plan(candidates: candidates, archive: self)
        deletedIDs.formUnion(plan.tombstones)
        entries.removeAll { deletedIDs.contains($0.id) }
        entries.append(contentsOf: plan.recoverable)
        entries.append(contentsOf: plan.confirmedRemote.map { RoomChatEntry(message: $0, delivery: .sent) })
        return plan
    }

    mutating func recoverInterruptedSends() {
        for index in entries.indices where entries[index].delivery == .sending {
            entries[index].delivery = .failed
        }
    }
}

/// One scoped envelope per file, stored under app-private Application Support
/// by the integration layer. A wrong account/room refuses to load the file.
struct RoomChatArchive {
    enum ArchiveError: Error { case unsupportedVersion, scopeMismatch }
    private struct Envelope: Codable {
        let version: Int
        let state: RoomChatState
    }
    let url: URL

    func save(_ state: RoomChatState) throws {
        let data = try JSONEncoder().encode(Envelope(version: 1, state: state))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func load(scope: RoomChatScope) throws -> RoomChatState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return try RoomChatState(scope: scope)
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.version == 1 else { throw ArchiveError.unsupportedVersion }
        guard envelope.state.scope == scope else { throw ArchiveError.scopeMismatch }
        var state = envelope.state
        state.recoverInterruptedSends()
        return state
    }
}
