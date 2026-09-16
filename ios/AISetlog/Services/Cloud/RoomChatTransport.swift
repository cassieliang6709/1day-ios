import Foundation
import CloudKit

protocol RoomChatTransport {
    func fetch(roomCode: String) async throws -> [RoomChatMessage]
    func send(_ message: RoomChatMessage) async throws
    func delete(_ message: RoomChatMessage, accountID: String) async throws
    /// Returns only IDs whose direct lookup explicitly reports unknownItem.
    func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID>
}

/// Uses the existing Comment schema. Room messages omit day/targetAuthorID;
/// legacy comments keep their optional moment as context. No new record type.
struct CloudRoomChatTransport: RoomChatTransport {
    enum TransportError: Error { case incompletePage, malformedRecord, missingAcknowledgement, notAuthor }
    private var database: CKDatabase {
        CKContainer(identifier: CloudKitService.containerID).publicCloudDatabase
    }

    func fetch(roomCode: String) async throws -> [RoomChatMessage] {
        try await CloudKitService.ensureAccountAvailable()
        let query = CKQuery(recordType: "Comment", predicate: NSPredicate(format: "roomCode == %@", roomCode))
        var page = try await database.records(matching: query)
        var messages: [RoomChatMessage] = []
        for _ in 0..<50 {
            for (_, result) in page.matchResults {
                let record = try result.get() // Partial failures are not an empty conversation.
                messages.append(try RoomChatRecordCodec.decode(record, roomCode: roomCode))
            }
            guard let cursor = page.queryCursor else { return messages }
            try Task.checkCancellation()
            page = try await database.records(continuingMatchFrom: cursor)
        }
        throw TransportError.incompletePage
    }

    func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID> {
        var missing: Set<UUID> = []
        let values = Array(ids)
        for offset in stride(from: 0, to: values.count, by: 100) {
            try Task.checkCancellation()
            let batch = Array(values[offset..<min(offset + 100, values.count)])
            let results = try await database.records(for: batch.map { CKRecord.ID(recordName: $0.uuidString) })
            for id in batch {
                guard let result = results[CKRecord.ID(recordName: id.uuidString)] else {
                    throw TransportError.missingAcknowledgement
                }
                do {
                    let record = try result.get()
                    guard record["roomCode"] as? String == roomCode else { throw TransportError.malformedRecord }
                } catch let error as CKError where error.code == .unknownItem {
                    missing.insert(id)
                }
            }
        }
        return missing
    }

    func delete(_ message: RoomChatMessage, accountID: String) async throws {
        guard message.authorID == accountID else { throw TransportError.notAuthor }
        try await CloudKitService.ensureAccountAvailable()
        let id = CKRecord.ID(recordName: message.id.uuidString)
        do {
            let record = try await database.record(for: id)
            guard record["authorID"] as? String == accountID,
                  record["roomCode"] as? String == message.roomCode else { throw TransportError.notAuthor }
            // CloudKit permissions, not this client check, enforce server authorization.
            _ = try await database.deleteRecord(withID: id)
        } catch let error as CKError where error.code == .unknownItem {
            return // Already deleted, so retry is idempotent.
        }
    }

    func send(_ message: RoomChatMessage) async throws {
        try await CloudKitService.ensureAccountAvailable()
        let record = RoomChatRecordCodec.encode(message)
        let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        guard let result = saved[record.recordID] else { throw TransportError.missingAcknowledgement }
        _ = try result.get()
    }
}
