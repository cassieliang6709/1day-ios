import Foundation

@MainActor
final class AccountDeletionService {
    enum State: Equatable {
        case idle
        case running(done: Int, total: Int)
        case completed
        case failed(String)
    }

    private(set) var state: State = .idle

    private let store: ChallengeStore
    private let journalURL: URL
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

    @discardableResult
    func run() async -> Bool {
        guard let accountID = store.account?.account?.id, accountID != "local" else {
            state = .failed("no-account")
            return false
        }
        guard store.effects.allowsCloudRoomManagement else {
            state = .failed("preview-runtime")
            return false
        }

        await store.restoreMyRooms()
        for code in store.challenges.compactMap(\.roomCode) {
            _ = await store.roomSync.syncClips(code: code)
            if let interactions = await store.roomSync.fetchInteractions(code: code) {
                store.roomSync.remoteReactions[code] = interactions.reactions
                store.roomSync.remoteComments[code] = interactions.comments
            }
        }
        let inventory = Self.inventory(of: store, authorID: accountID)

        let coordinator: AccountDeletionCoordinator
        do {
            let journal = try AccountDeletionJournalStore(url: journalURL, accountID: accountID)
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

    private static let maximumSteps = 400

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

    static func inventory(of store: ChallengeStore, authorID: String) -> [String] {
        var names: Set<String> = []
        for challenge in store.challenges {
            guard let code = challenge.roomCode else { continue }
            names.insert(CloudKitService.memberRecordName(code: code, authorID: authorID))
            for card in challenge.cards {
                names.insert(CloudKitService.clipRecordName(
                    code: code, authorID: authorID, day: card.day))
                for comment in card.comments where comment.authorID == authorID {
                    names.insert(comment.id.uuidString)
                }
            }
            names.formUnion(store.extraTakeRecordNames(in: challenge, authorID: authorID))
            for clip in store.roomSync.remoteClips[code] ?? [] where clip.authorID == authorID {
                names.insert(clip.id)
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
        return names.sorted()
    }

    private static func code(for error: Error) -> String {
        switch error {
        case is AccountDeletionCoordinator.Failure: "protocol"
        case is AccountDeletionProgress.TransitionError: "protocol"
        case is AccountDeletionJournalStore.Failure: "journal"
        default: "network"
        }
    }
}
