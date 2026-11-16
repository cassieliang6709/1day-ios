import Foundation

enum RoomChatRecordCodec {
    static func decode(_ body: CloudKitService.CommentBody, roomCode: String) throws -> RoomChatMessage {
        guard let id = UUID(uuidString: body.id),
              body.roomCode == roomCode,
              !body.authorID.isEmpty
        else { throw CloudRoomChatTransport.TransportError.malformedRecord }
        return RoomChatMessage(
            id: id, roomCode: body.roomCode, authorID: body.authorID,
            authorName: body.authorName, text: body.text,
            createdAt: Date(apiMillis: body.createdAt),
            moment: body.day.flatMap { $0 > 0 ? $0 : nil })
    }

    static func encode(_ message: RoomChatMessage) -> CloudKitService.CommentWrite {
        CloudKitService.CommentWrite(
            roomCode: message.roomCode, day: message.moment, text: message.text,
            authorName: message.authorName, targetAuthorID: nil,
            createdAt: message.createdAt.apiMillis)
    }
}

struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
