import Foundation

/// Turning "今天要搬家" into the seven things worth pointing a camera at.
///
/// The problem this solves is the one that makes people give up on the custom
/// path: a day that hasn't happened yet is hard to write prompts for, so what
/// gets written is generic, and generic prompts produce a film about nothing.
/// But "今天要搬家" is sayable right now, before any of it has happened.
///
/// This is an accelerator, never a gate. Every failure is silent and lands the
/// user back where they already were — in front of an editable list they can
/// fill in themselves. There is no error state worth interrupting someone for
/// here, because the thing they were doing still works.
protocol PromptSuggesting: Sendable {
    func suggest(intent: String, count: Int, language: AppLanguage) async throws -> [String]
}

enum PromptSuggestionError: Error, Equatable {
    /// The server answered, but not with prompts we can use.
    case malformed
    /// Too many calls from this device.
    case rateLimited
    /// No network, timed out, or the server is down. All the same to the user.
    case unavailable
}

/// Calls the one-purpose Cloudflare Worker in `workers/suggest-prompts`.
///
/// The API key lives on the server. A key shipped inside the app is a key
/// somebody else is going to spend.
struct RemotePromptSuggestionService: PromptSuggesting {
    static let defaultEndpoint = URL(
        string: "https://oneday-suggest-prompts.oneday-cassie.workers.dev/api/suggest-prompts")!

    /// Long enough for a model round-trip, short enough that a hung network
    /// doesn't leave someone watching a spinner instead of writing prompts.
    static let timeout: TimeInterval = 20

    var session: URLSession = .shared
    var endpoint: URL = RemotePromptSuggestionService.defaultEndpoint
    /// Opaque, per-install, and only used for rate limiting.
    var deviceID: String = DeviceIdentity.installID

    func suggest(intent: String, count: Int, language: AppLanguage) async throws -> [String] {
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

        return try Self.prompts(from: data, wanted: count)
    }

    /// Split out from the request so the parsing rules can be tested without a
    /// server: a model writing free text is exactly the kind of input that
    /// arrives malformed eventually.
    static func prompts(from data: Data, wanted: Int) throws -> [String] {
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw PromptSuggestionError.malformed
        }
        let prompts = decoded.prompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(max(wanted, 1))

        // Two is what the composer needs to make a story at all. Fewer than
        // that isn't a shorter answer, it's a broken one.
        guard prompts.count >= 2 else { throw PromptSuggestionError.malformed }
        return Array(prompts)
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

/// A random id minted on first use and kept in UserDefaults.
///
/// Not `identifierForVendor`: that one is stable across a reinstall for the
/// same vendor and is a real device identifier. This is a number that means
/// nothing anywhere else, which is all a rate limiter needs.
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
