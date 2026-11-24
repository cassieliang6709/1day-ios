import Foundation

struct ClipPickInput: Encodable, Sendable {
    var id: String
    var day: String
    var time: String
    var seconds: Int
    var faces: Int
    var labels: [String]
}

struct ClipPick: Equatable, Sendable {
    var ids: [String]
    var title: String?
}

enum ClipPickError: Error, Equatable {
    case rateLimited
    case unavailable
}

struct RemoteClipPicker: Sendable {
    static let defaultEndpoint = URL(string: "https://oneday-api.liangyue.site/api/pick-clips")!
    static let timeout: TimeInterval = 8

    var session: URLSession = .shared
    var endpoint: URL = RemoteClipPicker.defaultEndpoint
    var deviceID: String = DeviceIdentity.installID

    func pick(_ clips: [ClipPickInput], targetSeconds: Int, language: AppLanguage) async throws -> ClipPick {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            Request(
                clips: clips,
                targetSeconds: targetSeconds,
                language: language.resolved == .chinese ? "zh" : "en",
                device: deviceID))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClipPickError.unavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw ClipPickError.rateLimited }
        guard status == 200, let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ClipPickError.unavailable
        }
        let known = Set(clips.map(\.id))
        let ids = decoded.ids.filter(known.contains)
        guard !ids.isEmpty else { throw ClipPickError.unavailable }
        let title = decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClipPick(ids: ids, title: title.flatMap { $0.isEmpty ? nil : String($0.prefix(40)) })
    }

    private struct Request: Encodable {
        var clips: [ClipPickInput]
        var targetSeconds: Int
        var language: String
        var device: String
    }

    private struct Response: Decodable {
        var ids: [String]
        var title: String?
    }
}
