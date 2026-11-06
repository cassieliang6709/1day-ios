import XCTest
@testable import AISetlog

final class RoomChatRecordCodecTests: XCTestCase {
    private func message(moment: Int? = nil) -> RoomChatMessage {
        .init(id: UUID(), roomCode: "ABCDEF", authorID: "alice", authorName: "Alice",
              text: "你好 👋", createdAt: Date(timeIntervalSince1970: 123), moment: moment)
    }

    /// What the Worker would send back for a message this phone wrote.
    private func row(for message: RoomChatMessage, targetAuthorID: String? = nil) -> CloudKitService.CommentBody {
        let write = RoomChatRecordCodec.encode(message)
        return .init(id: message.id.uuidString, roomCode: write.roomCode, day: write.day,
                     text: write.text, authorID: message.authorID, authorName: write.authorName,
                     targetAuthorID: targetAuthorID, createdAt: write.createdAt ?? 0)
    }

    func testRoomMessageCarriesNoFakeMomentOrTarget() throws {
        let original = message()
        let write = RoomChatRecordCodec.encode(original)
        XCTAssertNil(write.day)
        XCTAssertNil(write.targetAuthorID)
        XCTAssertEqual(try RoomChatRecordCodec.decode(row(for: original), roomCode: "ABCDEF"), original)
    }

    func testOldTargetedCommentsRemainReadableAcrossMoments() throws {
        for moment in [1, 7] {
            let original = message(moment: moment)
            XCTAssertEqual(
                try RoomChatRecordCodec.decode(row(for: original, targetAuthorID: "bob"), roomCode: "ABCDEF"),
                original)
        }
    }

    func testRetryKeepsOriginalTimestamp() {
        let original = message()
        XCTAssertEqual(RoomChatRecordCodec.encode(original).createdAt, 123_000)
        XCTAssertEqual(RoomChatRecordCodec.encode(original).createdAt, RoomChatRecordCodec.encode(original).createdAt)
    }

    func testWrongRoomAndMalformedRowFailExplicitly() {
        let good = row(for: message())
        XCTAssertThrowsError(try RoomChatRecordCodec.decode(good, roomCode: "OTHER"))
        let noAuthor = CloudKitService.CommentBody(
            id: good.id, roomCode: good.roomCode, day: nil, text: "x", authorID: "",
            authorName: "", targetAuthorID: nil, createdAt: 0)
        XCTAssertThrowsError(try RoomChatRecordCodec.decode(noAuthor, roomCode: "ABCDEF"))
    }

    /// One row that didn't parse used to throw for the whole conversation, so
    /// nobody in the room saw any new message.
    func testOneBadRowDoesNotHideTheRestOfTheConversation() throws {
        let good = [message(), message()]
        let json = """
        {"comments": [
          \(try encodeRow(row(for: good[0]))),
          {"id": "not-a-uuid-and-missing-fields"},
          \(try encodeRow(row(for: good[1])))
        ]}
        """
        struct Body: Decodable { let comments: [Lossy<CloudKitService.CommentBody>] }
        let body = try JSONDecoder().decode(Body.self, from: Data(json.utf8))

        let decoded = CloudRoomChatTransport.decodeMatches(body.comments.map(\.value), roomCode: "ABCDEF")

        XCTAssertEqual(decoded, good)
    }

    private func encodeRow(_ row: CloudKitService.CommentBody) throws -> String {
        """
        {"id":"\(row.id)","roomCode":"\(row.roomCode)","day":null,"text":"\(row.text)",\
        "authorID":"\(row.authorID)","authorName":"\(row.authorName)","targetAuthorID":null,\
        "createdAt":\(row.createdAt)}
        """
    }
}
