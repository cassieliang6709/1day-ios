import Foundation

/// Pure mapping between a room message and the Worker's comment rows,
/// testable without a network. Scope is always the room; `day` and
/// `targetAuthorID` on older per-clip comments are context, not filters.
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

    /// A room message leaves `day` and `targetAuthorID` out, and carries its
    /// own `createdAt` so a retry keeps the time it was written.
    static func encode(_ message: RoomChatMessage) -> CloudKitService.CommentWrite {
        CloudKitService.CommentWrite(
            roomCode: message.roomCode, day: message.moment, text: message.text,
            authorName: message.authorName, targetAuthorID: nil,
            createdAt: message.createdAt.apiMillis)
    }
}

/// One element of a JSON array that may not decode, so one bad row doesn't
/// fail the whole list.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
