import XCTest
import CloudKit
@testable import AISetlog

final class RoomChatRecordCodecTests: XCTestCase {
    private func message(moment: Int? = nil) -> RoomChatMessage {
        .init(id: UUID(), roomCode: "ABCDEF", authorID: "alice", authorName: "Alice",
              text: "你好 👋", createdAt: Date(timeIntervalSince1970: 123), moment: moment)
    }

    func testRoomMessageNeedsNoNewSchemaFieldsOrFakeMoment() throws {
        let original = message()
        let record = RoomChatRecordCodec.encode(original)
        XCTAssertEqual(record.recordType, "Comment")
        XCTAssertNil(record["day"])
        XCTAssertNil(record["targetAuthorID"])
        XCTAssertEqual(Set(record.allKeys()), Set(["roomCode", "authorID", "authorName", "text", "createdAt"]))
        XCTAssertEqual(try RoomChatRecordCodec.decode(record, roomCode: "ABCDEF"), original)
    }

    func testOldTargetedCommentsRemainReadableAcrossMoments() throws {
        for moment in [1, 7] {
            let original = message(moment: moment)
            let record = RoomChatRecordCodec.encode(original)
            record["targetAuthorID"] = "bob" as CKRecordValue
            XCTAssertEqual(try RoomChatRecordCodec.decode(record, roomCode: "ABCDEF"), original)
        }
    }

    func testRetryKeepsRecordIdentityAndOriginalTimestamp() {
        let original = message()
        let first = RoomChatRecordCodec.encode(original)
        let retry = RoomChatRecordCodec.encode(original)
        XCTAssertEqual(first.recordID, retry.recordID)
        XCTAssertEqual(first["createdAt"] as? Date, retry["createdAt"] as? Date)
    }

    func testWrongRoomAndMalformedRecordFailExplicitly() {
        let record = RoomChatRecordCodec.encode(message())
        XCTAssertThrowsError(try RoomChatRecordCodec.decode(record, roomCode: "OTHER"))
        record["authorID"] = nil
        XCTAssertThrowsError(try RoomChatRecordCodec.decode(record, roomCode: "ABCDEF"))
    }

    /// One record that failed to load or parse used to throw for the whole
    /// conversation, so nobody in the room saw any new message.
    func testOneBadRecordDoesNotHideTheRestOfTheConversation() {
        let good = [message(), message()]
        let goodRecords = good.map(RoomChatRecordCodec.encode)
        let malformed = RoomChatRecordCodec.encode(message())
        malformed["text"] = nil
        let failedID = CKRecord.ID(recordName: UUID().uuidString)
        let matches: [(CKRecord.ID, Result<CKRecord, Error>)] = [
            (goodRecords[0].recordID, .success(goodRecords[0])),
            (failedID, .failure(CKError(.permissionFailure))),
            (malformed.recordID, .success(malformed)),
            (goodRecords[1].recordID, .success(goodRecords[1])),
        ]

        let decoded = CloudRoomChatTransport.decodeMatches(matches, roomCode: "ABCDEF")

        XCTAssertEqual(decoded, good)
    }
}
