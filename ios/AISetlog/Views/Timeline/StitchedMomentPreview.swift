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

    private static var cache: [String: URL] = [:]

    private var cacheKey: String {
        if previewMedia != nil { return LocalRoomMediaKey.make(day: day, clips: clips) }
        return "\(day)-" + clips.map(\.id).joined(separator: "-")
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
        guard clips.count > 1, stitched == nil else { return }
        let cached: URL?
        if let previewMedia {
            cached = previewMedia.cached(cacheKey)
        } else {
            cached = Self.cache[cacheKey]
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
                guard previewMedia.accept(url, key: cacheKey) else {
                    stitchFailed = true
                    return
                }
            } else {
                Self.cache[cacheKey] = url
            }
            stitched = url
        } catch {
            guard !Task.isCancelled else { return }
            print("[moment] stitch failed: \(error)")
            stitchFailed = true
        }
    }
}
