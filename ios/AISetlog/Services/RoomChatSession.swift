import Foundation
import Combine
import CryptoKit

@MainActor
final class RoomChatSession: ObservableObject {
    @Published private(set) var state: RoomChatState?
    @Published private(set) var error: Failure?
    enum Failure { case storage, fetch, send, delete, messageTooLong }
    @Published private(set) var deletingIDs: Set<UUID> = []
    private let archive: RoomChatArchive
    private let transport: any RoomChatTransport
    private var refreshing = false
    private let identityIsCurrent: () -> Bool

    init(scope: RoomChatScope, directory: URL, transport: any RoomChatTransport = CloudRoomChatTransport(),
         identityIsCurrent: @escaping () -> Bool) {
        self.transport = transport
        self.identityIsCurrent = identityIsCurrent
        // Hash the encoded tuple, not a concatenation that could collide at delimiters.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let key = (try? encoder.encode(scope)) ?? Data()
        let filename = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        archive = RoomChatArchive(url: directory.appendingPathComponent(filename + ".json"))
        do {
            if identityIsCurrent() { state = try archive.load(scope: scope) }
        }
        catch { self.error = .storage }
    }

    /// Invalid sessions drop in-memory contents and stop disk mutations. The
    /// archived draft/outbox is retained for an intentional later login.
    private func validateIdentity() -> Bool {
        guard identityIsCurrent() else {
            state = nil
            error = nil
            return false
        }
        return state != nil
    }

    /// Explicit recovery only: the caller must supply audited provenance. No
    /// fetch omission is promoted to "never uploaded", and nothing is sent.
    /// Synchronous on the session actor, so sends/refreshes cannot interleave
    /// between taking current state and atomically saving the recovered state.
    @discardableResult
    func recoverLegacyComments(_ candidates: [LegacyRoomChatMigration.Candidate]) -> LegacyRoomChatMigration.Plan? {
        guard validateIdentity(), let current = state else { return nil }
        do {
            let result = try LegacyRoomChatRecovery.recover(candidates: candidates, scope: current.scope,
                                                            load: { current }, save: archive.save)
            state = result.state
            if error == .storage { error = nil }
            return result.plan
        } catch {
            self.error = .storage
            return nil
        }
    }

    func setDraft(_ text: String) {
        guard validateIdentity(), var next = state else { return }
        next.draft = text
        // Retain text on screen even on disk failure, and tell the user it isn't safe.
        state = next
        do { try archive.save(next); if error == .storage { error = nil } }
        catch { self.error = .storage }
    }

    func send(authorName: String, moment: Int? = nil) async {
        guard validateIdentity(), var next = state else { return }
        do {
            let message = try next.enqueue(authorName: authorName, moment: moment)
            try archive.save(next) // Do not clear the composer before durable enqueue.
            state = next
            await transmit(message)
        } catch RoomChatState.StateError.messageTooLong { self.error = .messageTooLong }
        catch { self.error = .storage }
    }

    func retry(_ id: UUID) async {
        guard validateIdentity(), var next = state else { return }
        do {
            let message = try next.retry(id)
            try archive.save(next)
            state = next
            await transmit(message)
        } catch { self.error = .storage }
    }

    private func transmit(_ message: RoomChatMessage) async {
        guard validateIdentity() else { return }
        do {
            try Task.checkCancellation()
            try await transport.send(message)
            guard validateIdentity(), var next = state else { return }
            try next.acknowledge(message)
            try archive.save(next)
            state = next
            error = nil
        } catch {
            guard validateIdentity(), var next = state else { return }
            next.markFailed(message.id)
            state = next
            do { try archive.save(next); self.error = .send }
            catch { self.error = .storage }
        }
    }

    func delete(_ id: UUID) async {
        guard validateIdentity(), let entry = state?.entries.first(where: { $0.id == id }),
              let accountID = state?.scope.accountID,
              entry.message.authorID == accountID, entry.delivery == .sent,
              !deletingIDs.contains(id) else { return }
        deletingIDs.insert(id)
        defer { deletingIDs.remove(id) }
        do {
            try await transport.delete(entry.message, accountID: accountID)
        } catch {
            if validateIdentity() { self.error = .delete }
            return
        }
        guard validateIdentity(), var next = state else { return }
        next.confirmDeleted([id])
        state = next
        do { try archive.save(next); if error == .delete { error = nil } }
        catch { self.error = .storage }
    }

    func refresh() async {
        guard validateIdentity(), !refreshing, let scope = state?.scope else { return }
        refreshing = true
        defer { refreshing = false }
        // Capture before awaiting. A concurrently confirmed send must not be
        // judged missing by a fetch that began before the message was sent.
        let candidates = Set(state?.entries.filter { $0.delivery == .sent }.map(\.id) ?? [])
        let messages: [RoomChatMessage]
        let missing: Set<UUID>
        do {
            messages = try await transport.fetch(roomCode: scope.roomCode)
            guard validateIdentity() else { return }
            let absent = candidates.subtracting(messages.map(\.id))
            missing = absent.isEmpty ? [] : try await transport.confirmedMissing(absent, roomCode: scope.roomCode)
            try Task.checkCancellation()
        } catch is CancellationError { return }
        catch { if validateIdentity() { self.error = .fetch }; return }
        guard validateIdentity(), var next = state, next.scope == scope else { return }
        do {
            try next.mergeSuccessfulFetch(messages)
            next.confirmDeleted(missing.intersection(candidates))
        } catch { self.error = .fetch; return }
        do {
            try archive.save(next)
            state = next
            if error == .fetch { error = nil }
        } catch { self.error = .storage }
    }
}
