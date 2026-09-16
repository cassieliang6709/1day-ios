import Foundation
import CloudKit

/// Pure mapping of existing Comment fields, testable without an iCloud account.
/// Scope is always the room; day/targetAuthorID on older records are not filters.
enum RoomChatRecordCodec {
    static func decode(_ record: CKRecord, roomCode: String) throws -> RoomChatMessage {
        guard record.recordType == "Comment",
              let id = UUID(uuidString: record.recordID.recordName),
              let code = record["roomCode"] as? String, code == roomCode,
              let author = record["authorID"] as? String, !author.isEmpty,
              let text = record["text"] as? String else {
            throw CloudRoomChatTransport.TransportError.malformedRecord
        }
        let day = record["day"] as? Int
        return RoomChatMessage(id: id, roomCode: code, authorID: author,
            authorName: record["authorName"] as? String ?? "",
            text: text, createdAt: record["createdAt"] as? Date ?? record.creationDate ?? .distantPast,
            moment: day.flatMap { $0 > 0 ? $0 : nil })
    }

    static func encode(_ message: RoomChatMessage) -> CKRecord {
        let record = CKRecord(recordType: "Comment", recordID: .init(recordName: message.id.uuidString))
        record["roomCode"] = message.roomCode as CKRecordValue
        record["authorID"] = message.authorID as CKRecordValue
        record["authorName"] = message.authorName as CKRecordValue
        record["text"] = message.text as CKRecordValue
        record["createdAt"] = message.createdAt as CKRecordValue
        if let moment = message.moment { record["day"] = moment as CKRecordValue }
        return record
    }
}
