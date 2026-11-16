import SwiftUI

struct StitchedMomentPreview: View {
    let clips: [DayClip]
    let day: Int
    var slotTitle: String?
    var momentCount = 0
    var clipLength: Challenge.ClipLength = .tiny
    var challengeID: UUID?
    var showsPrompt = true
    let myID: String
    let onRecord: (TakeTarget) -> Void

    @Environment(\.roomPreviewMediaScope) private var previewMedia
    @State private var stitched: URL?
    @State private var stitchFailed = false
    /// Keep an evicted output alive for as long as this view still uses it.
    @State private var productionOutput: MomentPreviewOutput?

    private static let cache = MomentPreviewCache()

    private var cacheKey: String {
        LocalRoomMediaKey.make(day: day, clips: clips)
    }

    private var mine: DayClip? {
        clips.first { $0.authorID == myID || $0.authorID == "local" }
    }

    private var authorLine: String? {
        let names = clips.compactMap(\.authorName).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if clips.count <= 1, let only = clips.first {
                preview(url: only.url, authorName: only.authorName, captions: only.captions)
            } else if let stitched {
                preview(url: stitched, authorName: authorLine, captions: [])
            } else if stitchFailed, let fallback = mine ?? clips.first {
                preview(url: fallback.url, authorName: fallback.authorName,
                        captions: fallback.captions)
            } else {
                loading
            }
        }
        .task(id: cacheKey) { await stitch() }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            OneDayBuddy(size: 64, isWorking: true)
            Text(Strings.stitchingMoment)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneDayCanvas())
    }

    private func preview(
        url: URL, authorName: String?, captions: [Caption]
    ) -> some View {
        ClipPreviewView(
            day: day,
            slotTitle: slotTitle,
            momentCount: momentCount,
            authorName: authorName,
            captions: captions,
            clipLength: clipLength,
            showsPrompt: showsPrompt,
            url: url,
            recordedAt: clips.first?.recordedAt,
            challengeID: challengeID,
            targetAuthorID: mine?.authorID,
            onReRecord: { onRecord(.replace(nil)) },
            onAddTake: { onRecord(.append) })
    }

    private func stitch() async {
        stitched = nil
        productionOutput = nil
        stitchFailed = false
        guard clips.count > 1, !Task.isCancelled else { return }
        let requested = cacheKey
        let cached: URL?
        if let previewMedia {
            cached = previewMedia.cached(requested)
        } else {
            productionOutput = Self.cache.output(for: requested)
            cached = productionOutput?.url
        }
        if let cached,
           FileManager.default.fileExists(atPath: cached.path) {
            stitched = cached
            return
        }
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.showDayCaptions = false
        options.crossfadeSeconds = 0
        do {
            let url = try await VideoStitcher.stitch(clips: clips, options: options)
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            if let previewMedia {
                guard previewMedia.accept(url, key: requested) else {
                    stitchFailed = true
                    return
                }
            } else {
                let output = MomentPreviewOutput(url: url)
                Self.cache.store(output, for: requested)
                productionOutput = output
            }
            stitched = url
        } catch {
            guard !Task.isCancelled else { return }
            print("[moment] stitch failed: \(error)")
            stitchFailed = true
        }
    }
}

/// Derived files only. The cache and any visible preview share ownership, so
/// eviction never removes a file still being played by another preview.
final class MomentPreviewOutput {
    let url: URL

    init(url: URL) { self.url = url }

    deinit { try? FileManager.default.removeItem(at: url) }
}

@MainActor
final class MomentPreviewCache {
    private let capacity: Int
    private var entries: [String: MomentPreviewOutput] = [:]
    private var recent: [String] = []

    init(capacity: Int = 8) { self.capacity = max(1, capacity) }

    func output(for key: String) -> MomentPreviewOutput? {
        guard let output = entries[key] else { return nil }
        guard FileManager.default.fileExists(atPath: output.url.path) else {
            entries[key] = nil
            recent.removeAll { $0 == key }
            return nil
        }
        touch(key)
        return output
    }

    func store(_ output: MomentPreviewOutput, for key: String) {
        entries[key] = output
        touch(key)
        while recent.count > capacity {
            entries[recent.removeFirst()] = nil
        }
    }

    private func touch(_ key: String) {
        recent.removeAll { $0 == key }
        recent.append(key)
    }
}
