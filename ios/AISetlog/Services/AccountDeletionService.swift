import Foundation

/// Deleting an account, for real, and admitting it when that didn't work.
///
/// `AccountDeletionCoordinator` is the protocol — the phases, and what is safe
/// to do next given what's already durable. This is the composition root that
/// gives it somewhere to write, something to enumerate and something to delete,
/// and it is the piece that was missing: the app had the state machine and a
/// separate, older path that ignored it.
///
/// The rule that shapes everything here is that **local data is wiped last**.
/// The old path deleted the cloud records with `try?`, swept the device either
/// way, and signed the person out — so a network drop halfway through left
/// their clips on CloudKit, nothing on the phone to retry from, and a screen
/// that said they were gone. Wiping last means a failure is recoverable: the
/// journal survives, their stories are still here, and the next attempt picks
/// up where this one stopped.
@MainActor
final class AccountDeletionService {
    /// What the person on the other side of the screen needs to know.
    enum State: Equatable {
        case idle
        /// Working. The fraction is records confirmed gone, for a progress bar
        /// that is counting something real.
        case running(done: Int, total: Int)
        case completed
        /// Stopped part-way. Everything so far is durable and the next run
        /// resumes; nothing local has been touched yet.
        case failed(String)
    }

    private(set) var state: State = .idle

    private let store: ChallengeStore
    private let journalURL: URL
    /// Injected so tests can run the whole machine without a CloudKit account.
    private let deleteRecords: (Set<String>) async throws -> Set<String>

    init(
        store: ChallengeStore,
        journalURL: URL? = nil,
        deleteRecords: @escaping (Set<String>) async throws -> Set<String> = {
            try await CloudKitService.deleteRecordsConfirmingEachOne($0)
        }
    ) {
        self.store = store
        self.journalURL = journalURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("account-deletion.json")
        self.deleteRecords = deleteRecords
    }

    /// Runs the deletion to completion, or stops on the first failure with the
    /// journal intact.
    ///
    /// Returns true only when the account is actually gone. The caller must not
    /// show a success screen on false — that is the specific lie this whole file
    /// exists to stop telling.
    @discardableResult
    func run() async -> Bool {
        guard let accountID = store.account?.account?.id, accountID != "local" else {
            state = .failed("no-account")
            return false
        }
        guard store.effects.allowsCloudRoomManagement else {
            // A preview runtime owns its own teardown and must never reach a
            // real account's records.
            state = .failed("preview-runtime")
            return false
        }

        // The inventory is built once, from record names this app can
        // reconstruct, rather than from a query: `authorID` is not guaranteed
        // to be a queryable index in the production schema, and a query that
        // silently matches nothing is the worst possible outcome for something
        // somebody explicitly asked for.
        let inventory = Self.inventory(of: store, authorID: accountID)

        let coordinator: AccountDeletionCoordinator
        do {
            let journal = try AccountDeletionJournalStore(url: journalURL, accountID: accountID)
            // No writes are in flight because the caller has already frozen the
            // account; passing a set here would just mean waiting for them.
            let opening = try journal.begin(inFlightWrites: [])
            coordinator = AccountDeletionCoordinator(
                journal: opening,
                dependencies: .init(
                    save: { try journal.save($0) },
                    discover: { _, cursor in Self.page(of: inventory, after: cursor) },
                    delete: { [deleteRecords] _, batch in try await deleteRecords(batch) },
                    cleanLocal: { [store] _ in await store.wipeLocalAccountData() }))
        } catch {
            state = .failed("journal")
            return false
        }

        state = .running(done: 0, total: inventory.count)
        // Bounded rather than `while true`: `advance()` does one batch per call
        // by design, and a phase that stopped moving must end the run instead
        // of spinning against CloudKit forever.
        for _ in 0..<Self.maximumSteps {
            if coordinator.journal.progress.phase == .completed {
                state = .completed
                try? FileManager.default.removeItem(at: journalURL)
                return true
            }
            do {
                try await coordinator.advance()
            } catch {
                state = .failed(Self.code(for: error))
                return false
            }
            state = .running(
                done: coordinator.journal.progress.deletedRecordIDs.count,
                total: max(inventory.count, 1))
        }
        state = .failed("did-not-finish")
        return false
    }

    /// Enough for discovery, ~100-record delete batches over a large account,
    /// and the two bookend phases, with room to spare.
    private static let maximumSteps = 400

    /// A page of the inventory, addressed by an index held in the cursor.
    ///
    /// The coordinator rejects a cursor that repeats or comes back empty, so
    /// the index is rendered as a plain decimal and the last page reports nil.
    private static func page(
        of inventory: [String], after cursor: String?
    ) -> AccountDeletionCoordinator.Page {
        let size = 200
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(start + size, inventory.count)
        guard start < end else {
            return AccountDeletionCoordinator.Page(recordIDs: [], nextCursor: nil)
        }
        return AccountDeletionCoordinator.Page(
            recordIDs: Set(inventory[start..<end]),
            nextCursor: end < inventory.count ? String(end) : nil)
    }

    /// Every record name this person authored that the app can reconstruct.
    ///
    /// Rooms they created are deliberately absent. A room holds other people's
    /// clips too, and destroying a friend's story is not what "delete my
    /// account" should mean — the room survives with its owner's name stripped,
    /// which the local wipe step handles.
    static func inventory(of store: ChallengeStore, authorID: String) -> [String] {
        var names: Set<String> = []
        for challenge in store.challenges {
            guard let code = challenge.roomCode else { continue }
            for card in challenge.cards {
                names.insert(CloudKitService.clipRecordName(
                    code: code, authorID: authorID, day: card.day))
                for comment in card.comments where comment.authorID == authorID {
                    names.insert(comment.id.uuidString)
                }
            }
            for reaction in store.roomSync.remoteReactions[code] ?? []
            where reaction.authorID == authorID {
                names.insert(CloudKitService.reactionRecordName(
                    code: code, targetAuthorID: reaction.targetAuthorID,
                    authorID: authorID, day: reaction.day, emoji: reaction.emoji))
            }
            for comment in store.roomSync.remoteComments[code] ?? []
            where comment.authorID == authorID {
                names.insert(comment.id)
            }
        }
        // Sorted so a resumed run pages the same inventory in the same order as
        // the one it is resuming.
        return names.sorted()
    }

    /// A sanitized code, never a raw error: the journal is written to disk and
    /// CloudKit errors have been known to carry record contents.
    private static func code(for error: Error) -> String {
        switch error {
        case is AccountDeletionCoordinator.Failure: "protocol"
        case is AccountDeletionProgress.TransitionError: "protocol"
        case is AccountDeletionJournalStore.Failure: "journal"
        default: "network"
        }
    }
}
