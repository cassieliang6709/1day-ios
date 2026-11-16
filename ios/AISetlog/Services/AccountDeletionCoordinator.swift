import Foundation

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
        let delete: (String, Set<String>) async throws -> Set<String>
        let cleanLocal: (String) async throws -> Void
    }

    enum Failure: Error { case busy, invalidPage, invalidConfirmation }
    private(set) var journal: Journal
    private(set) var isRunning = false
    private let dependencies: Dependencies

    init(journal: Journal, dependencies: Dependencies) {
        self.journal = journal
        self.dependencies = dependencies
    }

    func settleWrite(_ token: UUID, recordIDs: Set<String>) throws {
        guard !isRunning else { throw Failure.busy }
        var next = journal
        try next.progress.settleWrite(token, writtenRecordIDs: recordIDs)
        try commit(next)
    }

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
