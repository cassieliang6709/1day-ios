import Foundation

enum RoomContentCache {
    static let confirmationGrace: TimeInterval = 120

    enum ConfirmedChange: Codable {
        case reaction(CloudKitService.RemoteReaction, on: Bool)
        case comment(CloudKitService.RemoteComment)
        case deletedComment(id: String, at: Date)

        private enum Target: Equatable {
            case reaction(day: Int, authorID: String, targetID: String, emoji: String)
            case comment(String)
        }

        private var target: Target {
            switch self {
            case .reaction(let value, _):
                return .reaction(day: value.day, authorID: value.authorID, targetID: value.targetAuthorID, emoji: value.emoji)
            case .comment(let value): return .comment(value.id)
            case .deletedComment(let id, _): return .comment(id)
            }
        }

        var at: Date {
            switch self {
            case .reaction(let value, _): return value.createdAt
            case .comment(let value): return value.createdAt
            case .deletedComment(_, let at): return at
            }
        }

        func replaces(_ other: ConfirmedChange) -> Bool { target == other.target }

        func apply(to value: inout Interactions) {
            switch self {
            case .reaction(let reaction, let on):
                value.reactions.removeAll {
                    $0.day == reaction.day && $0.authorID == reaction.authorID
                        && $0.targetAuthorID == reaction.targetAuthorID && $0.emoji == reaction.emoji
                }
                if on { value.reactions.append(reaction) }
            case .comment(let comment):
                value.comments.removeAll { $0.id == comment.id }
                value.comments.append(comment)
            case .deletedComment(let id, _): value.comments.removeAll { $0.id == id }
            }
        }
    }

    struct Interactions: Codable {
        var reactions: [CloudKitService.RemoteReaction] = []
        var comments: [CloudKitService.RemoteComment] = []
        var confirmedChanges: [ConfirmedChange]?

        mutating func confirm(_ change: ConfirmedChange, now: Date = .now) {
            var recent = (confirmedChanges ?? []).filter {
                now.timeIntervalSince($0.at) < RoomContentCache.confirmationGrace && !change.replaces($0)
            }
            recent.append(change)
            change.apply(to: &self)
            confirmedChanges = recent
        }

        func refreshing(with fresh: Interactions, now: Date = .now) -> Interactions {
            var merged = fresh
            let recent = (confirmedChanges ?? []).filter { now.timeIntervalSince($0.at) < RoomContentCache.confirmationGrace }
            for change in recent { change.apply(to: &merged) }
            merged.confirmedChanges = recent
            return merged
        }
    }

    private struct Snapshot<Value: Codable>: Codable {
        var schema = 1
        let accountID: String?
        let value: Value
    }

    private struct Clip: Codable {
        let id: String
        let day: Int
        let authorID: String
        let authorName: String
        let recordedAt: Date
        let fileName: String
        let overlayText: String?
        let captionSticker: CaptionSticker?
        let captionsJSON: String?
    }

    static func saveClips(_ clips: [CloudKitService.RemoteClip], in directory: URL, accountID: String?) throws {
        let records = clips.filter {
            $0.localURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
        }.map {
            Clip(id: $0.id, day: $0.day, authorID: $0.authorID, authorName: $0.authorName,
                 recordedAt: $0.recordedAt, fileName: $0.localURL.lastPathComponent,
                 overlayText: $0.overlayText, captionSticker: $0.captionSticker, captionsJSON: $0.captionsJSON)
        }
        try save(records, name: "clips.json", in: directory, accountID: accountID)
    }

    static func loadClips(in directory: URL, accountID: String?) -> [CloudKitService.RemoteClip]? {
        guard let clips: [Clip] = load(name: "clips.json", in: directory, accountID: accountID) else { return nil }
        return clips.compactMap { clip in
            guard !clip.fileName.isEmpty, clip.fileName != ".", clip.fileName != "..",
                  (clip.fileName as NSString).lastPathComponent == clip.fileName else { return nil }
            let url = directory.appendingPathComponent(clip.fileName)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { return nil }
            return CloudKitService.RemoteClip(
                id: clip.id, day: clip.day, authorID: clip.authorID, authorName: clip.authorName,
                recordedAt: clip.recordedAt, localURL: url, overlayText: clip.overlayText,
                captionSticker: clip.captionSticker, captionsJSON: clip.captionsJSON)
        }
    }

    static func saveInteractions(_ value: Interactions, in directory: URL, accountID: String?) throws {
        try save(value, name: "interactions.json", in: directory, accountID: accountID)
    }

    static func loadInteractions(in directory: URL, accountID: String?) -> Interactions? {
        load(name: "interactions.json", in: directory, accountID: accountID)
    }

    private static func save<Value: Codable>(
        _ value: Value, name: String, in directory: URL, accountID: String?
    ) throws {
        let data = try JSONEncoder().encode(Snapshot(accountID: accountID, value: value))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private static func load<Value: Codable>(name: String, in directory: URL, accountID: String?) -> Value? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
              let snapshot = try? JSONDecoder().decode(Snapshot<Value>.self, from: data),
              snapshot.schema == 1, snapshot.accountID == accountID else { return nil }
        return snapshot.value
    }
}
