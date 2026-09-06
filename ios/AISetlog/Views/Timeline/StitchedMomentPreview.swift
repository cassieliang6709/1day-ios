import SwiftUI

/// One moment, as it will look in the finished film: everyone who filmed it,
/// stacked together.
///
/// A grid tile stands for the moment rather than for one person's take, so
/// opening it and getting a single friend's clip answered the wrong question.
/// This stitches the slot on the fly with the film's own layout, and falls
/// straight through to plain playback when only one person filmed it.
struct StitchedMomentPreview: View {
    let clips: [DayClip]
    let day: Int
    var slotTitle: String?
    /// How many moments the story has, so playback can say "3 / 5".
    var momentCount = 0
    var clipLength: Challenge.ClipLength = .tiny
    var challengeID: UUID?
    var showsPrompt = true
    let myID: String
    let onReRecord: () -> Void

    @State private var stitched: URL?
    @State private var stitchFailed = false

    /// Stitching two clips takes a second or so; keeping the result means
    /// reopening the same moment is instant, and the temporary files don't
    /// pile up one per tap.
    private static var cache: [String: URL] = [:]

    private var cacheKey: String { "\(day)-" + clips.map(\.id).joined(separator: "-") }

    private var mine: DayClip? {
        clips.first { $0.authorID == myID || $0.authorID == "local" }
    }

    /// Whose takes are in this — the byline for the stitched version.
    private var authorLine: String? {
        let names = clips.compactMap(\.authorName).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if clips.count <= 1, let only = clips.first {
                preview(url: only.url, authorName: only.authorName, overlayText: only.overlayText)
            } else if let stitched {
                preview(url: stitched, authorName: authorLine, overlayText: nil)
            } else if stitchFailed, let fallback = mine ?? clips.first {
                // Better someone's clip than an empty sheet.
                preview(url: fallback.url, authorName: fallback.authorName,
                        overlayText: fallback.overlayText)
            } else {
                loading
            }
        }
        .task(id: cacheKey) { await stitch() }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            OneDayBuddy(size: 54, isWorking: true)
            Text(Strings.stitchingMoment)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneDayCanvas())
    }

    private func preview(url: URL, authorName: String?, overlayText: String?) -> some View {
        ClipPreviewView(
            day: day,
            slotTitle: slotTitle,
            momentCount: momentCount,
            authorName: authorName,
            overlayText: overlayText,
            clipLength: clipLength,
            showsPrompt: showsPrompt,
            url: url,
            recordedAt: clips.first?.recordedAt,
            challengeID: challengeID,
            targetAuthorID: mine?.authorID,
            onReRecord: onReRecord)
    }

    private func stitch() async {
        guard clips.count > 1, stitched == nil else { return }
        if let cached = Self.cache[cacheKey],
           FileManager.default.fileExists(atPath: cached.path) {
            stitched = cached
            return
        }
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        // No captions or crossfade: this is one moment, not a film.
        options.showDayCaptions = false
        options.crossfadeSeconds = 0
        // And no look, deliberately: this file goes to `ClipPreviewView`, which
        // filters as it plays. Baking it in here would apply it twice.
        do {
            let url = try await VideoStitcher.stitch(clips: clips, options: options)
            Self.cache[cacheKey] = url
            stitched = url
        } catch {
            print("[moment] stitch failed: \(error)")
            stitchFailed = true
        }
    }
}
