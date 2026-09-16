import Foundation

/// Explicitly local-only preview. This type has no CloudKit dependency and
/// never delegates to the production transport, even when sending/deleting.
@MainActor
final class RoomChatDemoTransport: RoomChatTransport {
    let scope = RoomChatScope(accountID: "demo-me", roomCode: "LOCAL-DEMO")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("1day-chat-demo-" + UUID().uuidString, isDirectory: true)
    private(set) var isClosed = false
    private var messages: [RoomChatMessage]

    init(chinese: Bool, now: Date = Date()) {
        let lines: [(Bool, String, Int?)] = chinese ? [
            (false, "今天的故事拍什么？", nil),
            (true, "先拍出发，再拍路上的风景。", nil),
            (false, "这段光线很好看 ☀️", 1),
            (true, "拍完直接发在房间里，我们晚上一起看。", nil),
            (false, "好呀！我想再拍一段回家的路。\n晚霞、路边的小店，还有今天吃到的东西，都可以放进同一个故事。", 3),
            (true, "好，回头见 👋", nil)
        ] : [
            (false, "What should we film today?", nil),
            (true, "Let's start with heading out and the views along the way.", nil),
            (false, "The light in this clip looks lovely ☀️", 1),
            (true, "Share it in the room and we'll watch it together tonight.", nil),
            (false, "Sounds good! I'll film the walk home too.\nThe sunset, little shops, and today's food can all be part of the same story.", 3),
            (true, "See you later 👋", nil)
        ]
        messages = lines.enumerated().map { index, line in
            RoomChatMessage(id: UUID(), roomCode: "LOCAL-DEMO",
                authorID: line.0 ? "demo-me" : "demo-friend",
                authorName: line.0 ? (chinese ? "我（演示）" : "Me (demo)") : (chinese ? "示例朋友" : "Sample friend"),
                text: line.1, createdAt: now.addingTimeInterval(Double(index - lines.count) * 90), moment: line.2)
        }
    }

    func fetch(roomCode: String) async throws -> [RoomChatMessage] {
        try validate(roomCode)
        return messages
    }

    func send(_ message: RoomChatMessage) async throws {
        try validate(message.roomCode)
        guard message.authorID == scope.accountID else { throw RoomChatState.StateError.invalidScope }
        try await Task.sleep(for: .milliseconds(250))
        try validate(message.roomCode)
        if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
    }

    func delete(_ message: RoomChatMessage, accountID: String) async throws {
        try validate(message.roomCode)
        guard accountID == scope.accountID, message.authorID == accountID else {
            throw RoomChatState.StateError.invalidScope
        }
        messages.removeAll { $0.id == message.id }
    }

    func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID> {
        try validate(roomCode)
        return ids.subtracting(messages.map(\.id))
    }

    func close() {
        isClosed = true // Invalidate the lease before removing any temporary archive.
        messages = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func validate(_ roomCode: String) throws {
        guard !isClosed else { throw CancellationError() }
        guard roomCode == scope.roomCode else { throw RoomChatState.StateError.wrongRoom }
    }
}
