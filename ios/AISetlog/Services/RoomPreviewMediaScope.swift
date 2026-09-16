import Foundation
import SwiftUI

/// Session-owned derived files and cache for the real room UI in local mode.
/// Never register source clips here. No global cache or production persistence.
@MainActor
final class RoomPreviewMediaScope {
    private var outputs: Set<URL> = []
    private var cache: [String: URL] = [:]
    private(set) var isClosed = false

    @discardableResult
    func accept(_ output: URL, key: String? = nil) -> Bool {
        guard !isClosed else {
            try? FileManager.default.removeItem(at: output)
            return false
        }
        outputs.insert(output)
        if let key { cache[key] = output }
        return true
    }

    func cached(_ key: String) -> URL? {
        guard !isClosed, let url = cache[key], FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        for output in outputs { try? FileManager.default.removeItem(at: output) }
        outputs = []
        cache = [:]
    }
}

private struct RoomPreviewMediaScopeKey: EnvironmentKey {
    static let defaultValue: RoomPreviewMediaScope? = nil
}

extension EnvironmentValues {
    var roomPreviewMediaScope: RoomPreviewMediaScope? {
        get { self[RoomPreviewMediaScopeKey.self] }
        set { self[RoomPreviewMediaScopeKey.self] = newValue }
    }
}
