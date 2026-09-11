import Foundation

/// Injectable cleanup executor. Deliberately has no live transport or automatic
/// account-store hookup: callers must freeze ALL writers and drain their leases
/// before discovery. Journal and cursor are committed together before advancing.
@MainActor
final class AccountDeletionCoordinator {
    struct Journal: Codable, Equatable {
        var progress: AccountDeletionProgress
        var cursor: String?
    }

    struct Page {
        let recordIDs: Set<String>
        let nextCursor: String?
    }

    struct Dependencies {
        let save: (Journal) throws -> Void
        let discover: (String, String?) async throws -> Page
        /// Return only individually confirmed successes. Unreturned IDs retry.
        /// Re-deleting an already absent record must be treated as success.
        let delete: (String, Set<String>) async throws -> Set<String>
        /// Must be idempotent; a crash/save failure can replay local cleanup.
        let cleanLocal: (String) async throws -> Void
    }

    enum Failure: Error { case busy, invalidPage, invalidConfirmation }
    private(set) var journal: Journal
    private(set) var isRunning = false
    private let dependencies: Dependencies

    /// The supplied journal must already be durable and its account frozen.
    init(journal: Journal, dependencies: Dependencies) {
        self.journal = journal
        self.dependencies = dependencies
    }

    /// The caller records the result of a registered, pre-freeze writer, even
    /// when its remote completion arrived after the user requested deletion.
    func settleWrite(_ token: UUID, recordIDs: Set<String>) throws {
        guard !isRunning else { throw Failure.busy }
        var next = journal
        try next.progress.settleWrite(token, writtenRecordIDs: recordIDs)
        try commit(next)
    }

    /// One bounded batch, never a hidden unbounded pagination/deletion loop.
    /// Throws on transport/disk failure; in-memory progress never outruns disk.
    /// The UI must retain the frozen state and show retry, not sign-out success.
    func advance() async throws {
        guard !isRunning else { throw Failure.busy }
        isRunning = true
        defer { isRunning = false }
        var next = journal
        let account = next.progress.accountID
        switch next.progress.phase {
        case .draining:
            try next.progress.beginDiscovery()
        case .discovering:
            let page = try await dependencies.discover(account, next.cursor)
            if let cursor = page.nextCursor {
                guard !cursor.isEmpty, cursor != next.cursor else { throw Failure.invalidPage }
            }
            try next.progress.discovered(page.recordIDs, isFinalPage: page.nextCursor == nil)
            next.cursor = page.nextCursor
        case .deleting:
            if next.progress.pendingRecordIDs.isEmpty {
                try next.progress.beginLocalCleanup()
            } else {
                let batch = Set(next.progress.pendingRecordIDs.sorted().prefix(100))
                let confirmed = try await dependencies.delete(account, batch)
                guard confirmed.isSubset(of: batch) else { throw Failure.invalidConfirmation }
                try next.progress.confirmedDeleted(confirmed)
            }
        case .localCleanup:
            try await dependencies.cleanLocal(account)
            try next.progress.confirmLocalCleanup()
        case .completed:
            return
        }
        try commit(next)
    }

    private func commit(_ next: Journal) throws {
        try dependencies.save(next)
        journal = next
    }
}
