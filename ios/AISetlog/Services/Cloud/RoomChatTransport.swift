import Foundation

protocol RoomChatTransport {
    func fetch(roomCode: String) async throws -> [RoomChatMessage]
    func send(_ message: RoomChatMessage) async throws
    func delete(_ message: RoomChatMessage, accountID: String) async throws
    /// Returns only IDs the server explicitly reports it has no record of.
    func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID>
}

/// Room chat on the Worker's comment rows, the same rows older per-clip
/// comments live in.
struct CloudRoomChatTransport: RoomChatTransport {
    enum TransportError: Error { case incompletePage, malformedRecord, missingAcknowledgement, notAuthor }
    var api: OneDayAPI = .shared

    func fetch(roomCode: String) async throws -> [RoomChatMessage] {
        struct Body: Decodable { let comments: [Lossy<CloudKitService.CommentBody>] }
        // A request that fails still throws: a partial conversation is not an
        // empty one. One bad row inside a good answer does not.
        let body = try await api.get(Body.self, ["rooms", roomCode, "comments"])
        return Self.decodeMatches(body.comments.map(\.value), roomCode: roomCode)
    }

    /// Decodes what decodes and logs the rest. One row that doesn't parse used
    /// to fail the whole fetch, so nobody in the room saw any new message
    /// until it went away. A skipped message is not mistaken for a deleted
    /// one: `confirmedMissing` asks the server directly.
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
            // An id that lives in another room is not this room's message, and
            // certainly not one to forget.
            guard response.elsewhere.isEmpty else { throw TransportError.malformedRecord }
            missing.formUnion(response.missing.compactMap(UUID.init(uuidString:)))
        }
        return missing
    }

    func delete(_ message: RoomChatMessage, accountID: String) async throws {
        guard message.authorID == accountID else { throw TransportError.notAuthor }
        // The Worker, not this check, enforces that only the author deletes;
        // an id already gone succeeds, so a retry is harmless.
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
