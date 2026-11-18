import Foundation

protocol RoomChatTransport {
    func fetch(roomCode: String) async throws -> [RoomChatMessage]
    func send(_ message: RoomChatMessage) async throws
    func delete(_ message: RoomChatMessage, accountID: String) async throws
    func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID>
}

struct CloudRoomChatTransport: RoomChatTransport {
    enum TransportError: Error { case incompletePage, malformedRecord, missingAcknowledgement, notAuthor }
    var api: OneDayAPI = .shared

    func fetch(roomCode: String) async throws -> [RoomChatMessage] {
        struct Body: Decodable { let comments: [Lossy<CloudKitService.CommentBody>] }
        let body = try await api.get(Body.self, ["rooms", roomCode, "comments"])
        return Self.decodeMatches(body.comments.map(\.value), roomCode: roomCode)
    }

    static func decodeMatches(_ rows: [CloudKitService.CommentBody?], roomCode: String) -> [RoomChatMessage] {
        rows.compactMap { row in
            guard let row else {
                print("[chat] skipped an unreadable row in \(roomCode)")
                return nil
            }
            do {
                return try RoomChatRecordCodec.decode(row, roomCode: roomCode)
            } catch {
                print("[chat] skipped record \(row.id) in \(roomCode): \(error)")
                return nil
            }
        }
    }

    func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID> {
        struct Request: Encodable { let ids: [String] }
        struct Response: Decodable { let missing: [String]; let elsewhere: [String] }
        var missing: Set<UUID> = []
        let values = Array(ids)
        for offset in stride(from: 0, to: values.count, by: 500) {
            try Task.checkCancellation()
            let batch = values[offset..<min(offset + 500, values.count)].map(\.uuidString)
            let data = try await api.send(
                "POST", ["rooms", roomCode, "comments", "missing"], json: Request(ids: batch))
            let response = try api.decode(Response.self, from: data)
            guard response.elsewhere.isEmpty else { throw TransportError.malformedRecord }
            missing.formUnion(response.missing.compactMap(UUID.init(uuidString:)))
        }
        return missing
    }

    func delete(_ message: RoomChatMessage, accountID: String) async throws {
        guard message.authorID == accountID else { throw TransportError.notAuthor }
        do {
            try await api.send("DELETE", ["comments", message.id.uuidString])
        } catch OneDayAPI.Failure.forbidden {
            throw TransportError.notAuthor
        }
    }

    func send(_ message: RoomChatMessage) async throws {
        try await api.send("PUT", ["comments", message.id.uuidString], json: RoomChatRecordCodec.encode(message))
    }
}
