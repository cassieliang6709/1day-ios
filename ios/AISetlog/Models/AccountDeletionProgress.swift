import Foundation

/// Durable protocol state, not an account-deletion implementation. The integration
/// layer must persist each transition before performing its next side effect.
/// In particular, freeze must be shared by every writer, not just chat UI.
struct AccountDeletionProgress: Codable, Equatable {
    enum Phase: String, Codable { case draining, discovering, deleting, localCleanup, completed }
    enum TransitionError: Error { case invalidPhase, writesInFlight, discoveryIncomplete, pendingRecords, invalidRecord }

    let accountID: String
    let operationID: UUID
    private(set) var phase: Phase = .draining
    private(set) var inFlightWrites: Set<UUID>
    private(set) var pendingRecordIDs: Set<String> = []
    private(set) var deletedRecordIDs: Set<String> = []
    private(set) var discoveryComplete = false
    private(set) var lastFailure: String?

    init(accountID: String, inFlightWrites: Set<UUID>, operationID: UUID = UUID()) throws {
        guard !accountID.isEmpty, accountID != "local" else { throw TransitionError.invalidRecord }
        self.accountID = accountID
        self.operationID = operationID
        self.inFlightWrites = inFlightWrites
    }

    // Remains frozen even when completed: only a separately established identity
    // may create a new write lease. Failure never reopens the old account.
    var allowsNewWrites: Bool { false }

    mutating func settleWrite(_ token: UUID, writtenRecordIDs: Set<String>) throws {
        guard phase == .draining, inFlightWrites.contains(token) else { throw TransitionError.invalidPhase }
        guard writtenRecordIDs.allSatisfy({ !$0.isEmpty }) else { throw TransitionError.invalidRecord }
        pendingRecordIDs.formUnion(writtenRecordIDs)
        inFlightWrites.remove(token)
    }

    mutating func beginDiscovery() throws {
        guard phase == .draining else { throw TransitionError.invalidPhase }
        guard inFlightWrites.isEmpty else { throw TransitionError.writesInFlight }
        phase = .discovering
        lastFailure = nil
    }

    /// Call only for a successfully received page, across ALL authored record
    /// types/rooms. The final-page signal must cover the entire inventory.
    mutating func discovered(_ records: Set<String>, isFinalPage: Bool) throws {
        guard phase == .discovering else { throw TransitionError.invalidPhase }
        guard records.allSatisfy({ !$0.isEmpty }) else { throw TransitionError.invalidRecord }
        pendingRecordIDs.formUnion(records.subtracting(deletedRecordIDs))
        if isFinalPage { discoveryComplete = true; phase = .deleting }
        lastFailure = nil
    }

    /// Partial batch successes are durable; unconfirmed records remain retryable.
    mutating func confirmedDeleted(_ records: Set<String>) throws {
        guard phase == .deleting else { throw TransitionError.invalidPhase }
        guard records.isSubset(of: pendingRecordIDs.union(deletedRecordIDs)) else {
            throw TransitionError.invalidRecord
        }
        pendingRecordIDs.subtract(records)
        deletedRecordIDs.formUnion(records)
        lastFailure = nil
    }

    mutating func beginLocalCleanup() throws {
        guard discoveryComplete else { throw TransitionError.discoveryIncomplete }
        guard phase == .deleting else { throw TransitionError.invalidPhase }
        guard pendingRecordIDs.isEmpty else { throw TransitionError.pendingRecords }
        phase = .localCleanup
        lastFailure = nil
    }

    mutating func confirmLocalCleanup() throws {
        guard phase == .localCleanup else { throw TransitionError.invalidPhase }
        phase = .completed
        lastFailure = nil
    }

    /// Store a sanitized error code, never raw credentials or user content.
    mutating func recordFailure(code: String) {
        guard phase != .completed else { return }
        lastFailure = code
    }
}
