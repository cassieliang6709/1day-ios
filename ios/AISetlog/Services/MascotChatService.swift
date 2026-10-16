import Foundation

/// 和小方块聊两句: one reply from the mascot to today's mood, note and the
/// short chat so far. Every failure ends up as a friendly fallback line in the
/// sheet, never an error dialog.
protocol MascotChatting: Sendable {
    func reply(mood: Mood, note: String, history: [MascotChatMessage], language: AppLanguage) async throws -> String
}

enum MascotChatError: Error, Equatable {
    case malformed
    case rateLimited
    case unavailable
}

/// Calls `/api/mascot-chat` on the same Worker as prompt suggestions.
/// Timeouts and the single retry mirror `RemotePromptSuggestionService`.
struct RemoteMascotChatService: MascotChatting {
    static let defaultEndpoint = URL(string: "https://oneday-api.liangyue.site/api/mascot-chat")!
    static let timeout: TimeInterval = RemotePromptSuggestionService.timeout
    static let attempts = RemotePromptSuggestionService.attempts

    var session: URLSession = .shared
    var endpoint: URL = RemoteMascotChatService.defaultEndpoint
    var deviceID: String = DeviceIdentity.installID

    func reply(mood: Mood, note: String, history: [MascotChatMessage], language: AppLanguage) async throws -> String {
        let body = Self.requestBody(mood: mood, note: note, history: history, language: language, device: deviceID)
        var lastError = MascotChatError.unavailable
        for _ in 0..<Self.attempts {
            do {
                return try await attempt(body)
            } catch MascotChatError.unavailable {
                lastError = .unavailable
                if Task.isCancelled { break }
            }
        }
        throw lastError
    }

    private func attempt(_ body: Data?) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MascotChatError.unavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw MascotChatError.rateLimited }
        guard status == 200 else { throw MascotChatError.unavailable }
        return try Self.reply(from: data)
    }

    /// The last messages only, matching the Worker's cap of 12.
    static func requestBody(mood: Mood, note: String, history: [MascotChatMessage],
                            language: AppLanguage, device: String) -> Data? {
        let messages = history.suffix(12).map { Request.Message(role: $0.role.rawValue, content: $0.content) }
        return try? JSONEncoder().encode(Request(
            mood: mood.rawValue,
            note: String(note.prefix(120)),
            language: language.resolved == .chinese ? "zh" : "en",
            device: device,
            messages: Array(messages)))
    }

    static func reply(from data: Data) throws -> String {
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw MascotChatError.malformed
        }
        let text = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MascotChatError.malformed }
        return text
    }

    private struct Request: Encodable {
        struct Message: Encodable { var role: String; var content: String }
        var mood: String
        var note: String
        var language: String
        var device: String
        var messages: [Message]
    }

    private struct Response: Decodable {
        var reply: String
    }
}
