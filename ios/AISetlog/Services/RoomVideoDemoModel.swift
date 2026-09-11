#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import AVFoundation
import Combine
import Foundation

/// Local media workspace. Never creates a Challenge or uploads a clip.
@MainActor
final class RoomVideoDemoModel: ObservableObject {
    @Published private(set) var clips: [DayClip] = []
    @Published private(set) var film: URL?
    @Published private(set) var filmRatio: CGFloat = 16.0 / 9
    @Published private(set) var busy = false
    @Published private(set) var failed = false
    private var closed = false
    private var revision = 0
    private var ownedURLs: Set<URL> = []

    func prepare(count: Int, landscape: Bool? = nil, chinese: Bool) async {
        guard !closed, (2...3).contains(count) else { return }
        revision += 1
        let token = revision
        busy = true
        failed = false
        film = nil
        defer { if token == revision { busy = false } }
        do {
            if clips.isEmpty {
                var generated: [DayClip] = []
                for index in 1...3 {
                    let name = chinese ? "示例成员 \(index)" : "Sample member \(index)"
                    guard let url = await DemoClipFactory.makeClip(moment: 1,
                        label: chinese ? "本地动态示例" : "Local motion sample", author: name,
                        seconds: 3, orientation: .portrait) else { throw CancellationError() }
                    guard !closed, token == revision, !Task.isCancelled else {
                        try? FileManager.default.removeItem(at: url)
                        throw CancellationError()
                    }
                    ownedURLs.insert(url)
                    generated.append(DayClip(day: 1, url: url, authorName: name, authorID: "demo-member-\(index)"))
                }
                clips = generated
            }
            let rendered = try await Self.stitch(Array(clips.prefix(count)), landscape: landscape)
            guard !closed, token == revision, !Task.isCancelled else {
                try? FileManager.default.removeItem(at: rendered)
                throw CancellationError()
            }
            ownedURLs.insert(rendered)
            let tracks = try await AVURLAsset(url: rendered).loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw VideoStitcher.StitchError.noClips }
            let size = try await track.load(.naturalSize)
            guard !closed, token == revision, !Task.isCancelled else { throw CancellationError() }
            filmRatio = size.width / size.height
            film = rendered
        } catch {
            if !closed, token == revision { failed = true }
        }
    }

    /// Uses the app's actual current friendsTogether compositor, including its
    /// current cropping behaviour. This is not a proposed replacement layout.
    static func stitch(_ clips: [DayClip], landscape: Bool? = nil) async throws -> URL {
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.showDayCaptions = false
        options.crossfadeSeconds = 0
        options.aspect = landscape.map { $0 ? .landscape : .portrait }
        return try await VideoStitcher.stitch(clips: clips, options: options)
    }

    /// Import a private copy, trim to the first three seconds, and never alter
    /// or upload the selected Photos asset. The picker owns permission to read.
    func replace(index: Int, source: URL, count: Int, landscape: Bool? = nil, chinese: Bool) async {
        defer { try? FileManager.default.removeItem(at: source) }
        guard !closed, !busy, clips.indices.contains(index) else { return }
        busy = true
        failed = false
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("room-demo-import-\(UUID()).mov")
        do {
            let asset = AVURLAsset(url: source)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0,
                  let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else {
                throw VideoStitcher.StitchError.compositionFailed
            }
            exporter.outputURL = output
            exporter.outputFileType = .mov
            exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: min(duration, 3), preferredTimescale: 600))
            await exporter.export()
            guard exporter.status == .completed, !closed else {
                throw VideoStitcher.StitchError.compositionFailed
            }
            ownedURLs.insert(output)
            let old = clips[index]
            clips[index] = DayClip(day: 1, url: output, authorName: old.authorName, authorID: old.authorID)
            busy = false
            await prepare(count: count, landscape: landscape, chinese: chinese)
        } catch {
            try? FileManager.default.removeItem(at: output)
            if !closed { failed = true; busy = false }
        }
    }

    func close() {
        closed = true
        revision += 1
        film = nil
        clips = []
        for url in ownedURLs { try? FileManager.default.removeItem(at: url) }
        ownedURLs.removeAll()
    }
}
#endif
