import Foundation

/// One owner on the main actor; not a cross-process lock. No default live path:
/// the account-deletion composition root must explicitly supply private storage.
/// A missing journal is distinct from corrupt/unsupported data (which throws).
@MainActor
final class AccountDeletionJournalStore {
    enum Failure: Error { case invalidAccount, wrongAccount, unsupportedVersion, missingJournal }
    private struct Envelope: Codable {
        let version: Int
        let journal: AccountDeletionCoordinator.Journal
    }
    private let url: URL
    private let accountID: String

    init(url: URL, accountID: String) throws {
        guard !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidAccount
        }
        self.url = url
        self.accountID = accountID
    }

    func load() throws -> AccountDeletionCoordinator.Journal? {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1 else { throw Failure.unsupportedVersion }
        try validate(envelope.journal)
        return envelope.journal
    }

    /// Resume existing progress, never reset a partially completed deletion.
    /// Persist this before freezing writers is reported as durable to the UI.
    func begin(inFlightWrites: Set<UUID>) throws -> AccountDeletionCoordinator.Journal {
        if let existing = try load() { return existing }
        let journal = AccountDeletionCoordinator.Journal(
            progress: try AccountDeletionProgress(accountID: accountID, inFlightWrites: inFlightWrites))
        try write(journal)
        return journal
    }

    /// Suitable for Coordinator.Dependencies.save. Refuses to silently replace
    /// missing, corrupt, future-version or another account's journal.
    func save(_ journal: AccountDeletionCoordinator.Journal) throws {
        try validate(journal)
        guard try load() != nil else { throw Failure.missingJournal }
        try write(journal)
    }

    private func validate(_ journal: AccountDeletionCoordinator.Journal) throws {
        guard journal.progress.accountID == accountID else { throw Failure.wrongAccount }
    }

    private func write(_ journal: AccountDeletionCoordinator.Journal) throws {
        try validate(journal)
        let data = try JSONEncoder().encode(Envelope(version: 1, journal: journal))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
