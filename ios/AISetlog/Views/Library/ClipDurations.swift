import AVFoundation

/// Clip lengths for the selection bar's 「约 8 秒」. Each file is opened once
/// and remembered; a file that can't be read counts as nothing.
enum ClipDurations {
    private static let cache = Cache()

    static func totalSeconds(of urls: [URL]) async -> Int? {
        guard !urls.isEmpty else { return nil }
        var total = 0.0
        for url in urls {
            guard !Task.isCancelled else { return nil }
            total += await cache.seconds(for: url)
        }
        return max(1, Int(total.rounded()))
    }

    private actor Cache {
        var known: [URL: Double] = [:]

        func seconds(for url: URL) async -> Double {
            if let seconds = known[url] { return seconds }
            let duration = try? await AVURLAsset(url: url).load(.duration)
            let seconds = duration.map(CMTimeGetSeconds).flatMap { $0.isFinite ? $0 : nil } ?? 0
            known[url] = seconds
            return seconds
        }
    }
}
