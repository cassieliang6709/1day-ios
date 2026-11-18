import Foundation

protocol PromptSuggesting: Sendable {
    func suggest(intent: String, count: Int, language: AppLanguage) async throws -> [String]
    func suggestStory(intent: String, count: Int, language: AppLanguage) async throws -> StorySuggestion
    func warmUp() async
}

struct StorySuggestion: Equatable, Sendable {
    var title: String?
    var prompts: [String]
}

extension PromptSuggesting {
    func suggestStory(intent: String, count: Int, language: AppLanguage) async throws -> StorySuggestion {
        StorySuggestion(title: nil, prompts: try await suggest(intent: intent, count: count, language: language))
    }

    func warmUp() async {}
}

enum PromptSuggestionError: Error, Equatable {
    case malformed
    case rateLimited
    case unavailable
}

struct RemotePromptSuggestionService: PromptSuggesting {
    static let defaultEndpoint = URL(
        string: "https://oneday-api.liangyue.site/api/suggest-prompts")!

    static let timeout: TimeInterval = 8
    static let attempts = 2

    var session: URLSession = .shared
    var endpoint: URL = RemotePromptSuggestionService.defaultEndpoint
    var deviceID: String = DeviceIdentity.installID

    func suggest(intent: String, count: Int, language: AppLanguage) async throws -> [String] {
        try await suggestStory(intent: intent, count: count, language: language).prompts
    }

    func warmUp() async {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        request.timeoutInterval = Self.timeout
        _ = try? await session.data(for: request)
    }

    func suggestStory(intent: String, count: Int, language: AppLanguage) async throws -> StorySuggestion {
        var lastError = PromptSuggestionError.unavailable
        for _ in 0..<Self.attempts {
            do {
                return try await attempt(intent: intent, count: count, language: language)
            } catch PromptSuggestionError.unavailable {
                lastError = .unavailable
                if Task.isCancelled { break }
            }
        }
        throw lastError
    }

    private func attempt(intent: String, count: Int, language: AppLanguage) async throws -> StorySuggestion {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            Request(
                intent: intent,
                count: count,
                language: language.resolved == .chinese ? "zh" : "en",
                device: deviceID))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PromptSuggestionError.unavailable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw PromptSuggestionError.rateLimited }
        guard status == 200 else { throw PromptSuggestionError.unavailable }

        return try Self.story(from: data, wanted: count)
    }

    static func prompts(from data: Data, wanted: Int) throws -> [String] {
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw PromptSuggestionError.malformed
        }
        let prompts = decoded.prompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(max(wanted, 1))

        guard prompts.count >= 2 else { throw PromptSuggestionError.malformed }
        return Array(prompts)
    }

    static func story(from data: Data, wanted: Int) throws -> StorySuggestion {
        let prompts = try prompts(from: data, wanted: wanted)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let title = (object?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return StorySuggestion(title: title.flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }, prompts: prompts)
    }

    private struct Request: Encodable {
        var intent: String
        var count: Int
        var language: String
        var device: String
    }

    private struct Response: Decodable {
        var prompts: [String]
    }
}

enum DeviceIdentity {
    static let storageKey = "promptSuggestion.installID"

    static var installID: String { installID(in: .standard) }

    static func installID(in defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: storageKey) { return existing }
        let minted = UUID().uuidString
        defaults.set(minted, forKey: storageKey)
        return minted
    }
}
