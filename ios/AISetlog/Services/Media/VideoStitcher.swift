import AVFoundation
import UIKit

enum VideoStitcher {

    enum Layout: Codable {
        case sequential
        case friendsTogether
    }

    struct TitleCard: Codable {
        let title: String
        let subtitle: String
    }

    enum Aspect: String, Codable, CaseIterable, Identifiable {
        case portrait, landscape, square

        var id: String { rawValue }

        var ratio: CGFloat {
            switch self {
            case .portrait: 9.0 / 16.0
            case .landscape: 16.0 / 9.0
            case .square: 1
            }
        }

        func renderSize(sourceLongEdge: CGFloat) -> CGSize {
            let short = (sourceLongEdge * 9 / 16).rounded()
            let long = sourceLongEdge.rounded()
            let raw: CGSize = switch self {
            case .portrait: CGSize(width: short, height: long)
            case .landscape: CGSize(width: long, height: short)
            case .square: CGSize(width: short, height: short)
            }
            return CGSize(
                width: (raw.width / 2).rounded(.down) * 2,
                height: (raw.height / 2).rounded(.down) * 2)
        }
    }

    struct Options: Codable {
        var crossfadeSeconds: Double = 0.35
        var showDayCaptions = true
        var layout: Layout = .sequential
        var titleCard: TitleCard?
        var titleSeconds: Double = 2.2
        var aspect: Aspect?
        var look: PersonalEffectParameters = .none
        var lookAuthorID: String?
        var keptClipIDs: Set<String>?
        var freezeFrames: [String: Double] = [:]
        var dayOrder: [Int]?
        static let `default` = Options()
    }

    enum StitchError: LocalizedError {
        case noClips
        case compositionFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noClips: return "No clips to stitch yet."
            case .compositionFailed: return "Could not build the video composition."
            case .exportFailed(let reason): return "Export failed: \(reason)"
            }
        }
    }

    private struct LoadedClip {
        let id: String
        let day: Int
        let label: String?
        let authorName: String?
        let captions: [Caption]
        let recordedAt: Date?
        let emoji: [String]
        let comments: [String]
        let asset: AVURLAsset
        let videoRange: CMTimeRange
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let audioRange: CMTimeRange
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        var frameDuration: CMTime = .invalid
        var hasCameraStamp = false
        var shownWhole: CGRect?

        var duration: CMTime { videoRange.duration }

        var orientedSize: CGSize {
            let r = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            return CGSize(width: abs(r.width), height: abs(r.height))
        }
    }

    private struct AuthorCaptionWindow {
        let text: String
        let sticker: CaptionSticker
        let cell: CGRect
        let start: Double
        let end: Double
    }

    private struct CaptionWindow {
        let day: Int
        let label: String?
        let authorName: String?
        let captions: [Caption]
        let recordedAt: Date?
        let emoji: [String]
        let comments: [String]
        let start: Double
        let end: Double
        var hasCameraStamp = false
        var captionFrame: CGRect?
    }


    static func stitch(
        clips allClips: [DayClip], options: Options = .default,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try Task.checkCancellation()
        let clips = kept(allClips, ids: options.keptClipIDs)
        guard !clips.isEmpty else { throw StitchError.noClips }

        #if !targetEnvironment(simulator)
        let drawCaptions = options.showDayCaptions
        let titleCard = options.titleCard
        #endif

        var cameraStamped: Set<String> = []
        for clip in clips where await CameraStyleBaker.hasCameraStamp(clip.url) {
            cameraStamped.insert(clip.id)
        }

        let (source, scratch) = try await filteredClips(
            clips, look: options.look, authorID: options.lookAuthorID)
        defer { discard(scratch) }
        progress?(0.2)

        var loaded: [LoadedClip] = []
        for clip in source {
            let asset = AVURLAsset(url: clip.url)
            guard let video = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let videoRange = try await video.load(.timeRange)
            let naturalSize = try await video.load(.naturalSize)
            let transform = try await video.load(.preferredTransform)
            let audio = try await asset.loadTracks(withMediaType: .audio).first
            let audioRange = audio == nil ? CMTimeRange.zero : try await audio!.load(.timeRange)
            let frameDuration = (try? await video.load(.minFrameDuration)) ?? .invalid
            loaded.append(LoadedClip(
                id: clip.id,
                day: clip.day, label: clip.label, authorName: clip.authorName,
                captions: clip.captions,
                recordedAt: clip.recordedAt,
                emoji: clip.emoji, comments: clip.comments,
                asset: asset, videoRange: videoRange, videoTrack: video,
                audioTrack: audio, audioRange: audioRange,
                naturalSize: naturalSize, preferredTransform: transform,
                frameDuration: frameDuration,
                hasCameraStamp: cameraStamped.contains(clip.id)))
        }
        guard !loaded.isEmpty else { throw StitchError.noClips }

        let landscapeCount = loaded.filter { $0.orientedSize.width > $0.orientedSize.height }.count
        let majorityLandscape = landscapeCount * 2 > loaded.count
        let firstSize = loaded.first { ($0.orientedSize.width > $0.orientedSize.height) == majorityLandscape }?
            .orientedSize ?? loaded[0].orientedSize
        let sourceAspect = firstSize.height > 0 ? firstSize.width / firstSize.height : 1
        let widestMoment: Int = switch options.layout {
        case .sequential: 1
        case .friendsTogether:
            Dictionary(grouping: loaded, by: \.day).values.map(\.count).max() ?? 1
        }
        let renderSize = options.aspect?
            .renderSize(sourceLongEdge: max(firstSize.width, firstSize.height))
            ?? mosaicRenderSize(
                count: widestMoment, sourceAspect: sourceAspect,
                longEdge: max(firstSize.width, firstSize.height))

        var reframeScratch: [URL] = []
        defer { discard(reframeScratch) }
        if case .sequential = options.layout {
            (loaded, reframeScratch) = try await reframed(loaded, canvas: renderSize)
        }

        #if targetEnvironment(simulator)
        let titleOffset = CMTime.zero
        #else
        let titleOffset = titleCard == nil
            ? CMTime.zero
            : CMTime(seconds: options.titleSeconds, preferredTimescale: 600)
        #endif

        let composition = AVMutableComposition()
        var instructions: [any AVVideoCompositionInstructionProtocol] = []
        var audioParams: [AVMutableAudioMixInputParameters] = []
        var captions: [CaptionWindow] = []
        var authorCaptions: [AuthorCaptionWindow] = []

        switch options.layout {
        case .sequential:
            try buildSequential(
                loaded: loaded, into: composition, renderSize: renderSize,
                crossfadeSeconds: options.crossfadeSeconds, startAt: titleOffset,
                instructions: &instructions, audioParams: &audioParams, captions: &captions)
        case .friendsTogether:
            try buildFriendsTogether(
                loaded: loaded, into: composition, renderSize: renderSize,
                sourceAspect: sourceAspect, freezeFrames: options.freezeFrames,
                dayOrder: options.dayOrder,
                startAt: titleOffset, instructions: &instructions,
                audioParams: &audioParams, captions: &captions,
                authorCaptions: &authorCaptions)
        }

        if titleOffset > .zero {
            let inst = AVMutableVideoCompositionInstruction()
            inst.timeRange = CMTimeRange(start: .zero, duration: titleOffset)
            inst.backgroundColor = UIColor.black.cgColor
            inst.layerInstructions = []
            instructions.insert(inst, at: 0)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions
        if case .friendsTogether = options.layout {
            videoComposition.customVideoCompositorClass = FriendsTogetherCompositor.self
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParams

        #if !targetEnvironment(simulator)
        do {
            let videoLayer = CALayer()
            videoLayer.frame = CGRect(origin: .zero, size: renderSize)
            let parentLayer = CALayer()
            parentLayer.frame = videoLayer.frame
            parentLayer.addSublayer(videoLayer)

            if let titleCard {
                addTitleCard(
                    titleCard, to: parentLayer, renderSize: renderSize,
                    duration: options.titleSeconds)
            }
            if drawCaptions {
                let multiAuthor = Set(
                    loaded.compactMap { $0.authorName?.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                ).count > 1
                for caption in captions {
                    addCaption(caption, to: parentLayer, renderSize: renderSize, showAuthorMark: multiAuthor)
                }
            }
            for caption in authorCaptions {
                addAuthorCaption(caption, to: parentLayer, renderSize: renderSize)
            }
            addWatermark(to: parentLayer, renderSize: renderSize)

            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        }
        #endif

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily_film_\(UUID().uuidString).mp4")

        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw StitchError.compositionFailed }

        export.outputURL = outURL
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.audioMix = audioMix

        print("[stitch] exporting clips=\(loaded.count) renderSize=\(renderSize)")
        try await VideoExportSession.run(export) { fraction in
            progress?(0.2 + fraction * 0.8)
        }
        guard export.status == .completed else {
            print("[stitch] export status=\(export.status.rawValue) error=\(String(describing: export.error))")
            throw StitchError.exportFailed(export.error?.localizedDescription ?? "unknown")
        }
        return outURL
    }


    private static func filteredClips(
        _ clips: [DayClip], look: PersonalEffectParameters, authorID: String?
    ) async throws -> (clips: [DayClip], scratch: [URL]) {
        guard !look.isIdentity else { return (clips, []) }

        var out: [DayClip] = []
        var scratch: [URL] = []
        for clip in clips {
            guard authorID == nil || clip.authorID == authorID else {
                out.append(clip)
                continue
            }
            do {
                let filtered = try await PersonalEffectFilter.filteredCopy(
                    of: clip.url, parameters: look)
                guard filtered != clip.url else { out.append(clip); continue }
                scratch.append(filtered)
                out.append(clip.replacingURL(filtered))
            } catch is CancellationError {
                discard(scratch)
                throw CancellationError()
            } catch {
                print("[stitch] look pass failed for day \(clip.day): \(error)")
                out.append(clip)
            }
        }
        return (out, scratch)
    }

    private static func discard(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }


    private struct Placement {
        let clip: LoadedClip
        let start: CMTime
        let trackIndex: Int
        var end: CMTime { CMTimeAdd(start, clip.duration) }
    }

    private static func buildSequential(
        loaded: [LoadedClip],
        into composition: AVMutableComposition,
        renderSize: CGSize,
        crossfadeSeconds: Double,
        startAt: CMTime,
        instructions: inout [any AVVideoCompositionInstructionProtocol],
        audioParams: inout [AVMutableAudioMixInputParameters],
        captions: inout [CaptionWindow]
    ) throws {
        var fade = CMTime(seconds: crossfadeSeconds, preferredTimescale: 600)
        if let shortest = loaded.map(\.duration).min() {
            let cap = CMTimeMultiplyByFloat64(shortest, multiplier: 0.45)
            if fade > cap { fade = cap }
        }
        if loaded.count == 1 { fade = .zero }

        var videoTracks: [AVMutableCompositionTrack] = []
        var audioTracks: [AVMutableCompositionTrack] = []
        for _ in 0..<2 {
            guard
                let v = composition.addMutableTrack(
                    withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                let a = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw StitchError.compositionFailed }
            videoTracks.append(v)
            audioTracks.append(a)
        }

        var placements: [Placement] = []
        var cursor = startAt
        for (i, clip) in loaded.enumerated() {
            let trackIndex = i % 2
            try videoTracks[trackIndex].insertTimeRange(clip.videoRange, of: clip.videoTrack, at: cursor)
            if let audio = clip.audioTrack {
                let audioDuration = CMTimeMinimum(clip.audioRange.duration, clip.duration)
                let audioRange = CMTimeRange(start: clip.audioRange.start, duration: audioDuration)
                try audioTracks[trackIndex].insertTimeRange(audioRange, of: audio, at: cursor)
            }
            placements.append(Placement(clip: clip, start: cursor, trackIndex: trackIndex))
            cursor = CMTimeAdd(cursor, clip.duration)
            if i < loaded.count - 1 { cursor = CMTimeSubtract(cursor, fade) }
        }

        for (i, p) in placements.enumerated() {
            let isFirst = i == 0
            let isLast = i == placements.count - 1
            let visibleStart = isFirst ? p.start : CMTimeAdd(p.start, fade)
            let visibleEnd = isLast ? p.end : CMTimeSubtract(p.end, fade)

            if visibleEnd > visibleStart {
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = CMTimeRange(start: visibleStart, end: visibleEnd)
                let layer = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: videoTracks[p.trackIndex])
                layer.setTransform(
                    fillTransform(for: p.clip, into: CGRect(origin: .zero, size: renderSize)),
                    at: visibleStart)
                inst.layerInstructions = [layer]
                instructions.append(inst)
            }

            if !isLast, fade > .zero {
                let next = placements[i + 1]
                let overlap = CMTimeRange(start: next.start, duration: fade)
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = overlap
                let outgoing = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: videoTracks[p.trackIndex])
                outgoing.setTransform(
                    fillTransform(for: p.clip, into: CGRect(origin: .zero, size: renderSize)),
                    at: next.start)
                outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: overlap)
                let incoming = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: videoTracks[next.trackIndex])
                incoming.setTransform(
                    fillTransform(for: next.clip, into: CGRect(origin: .zero, size: renderSize)),
                    at: next.start)
                inst.layerInstructions = [outgoing, incoming]
                instructions.append(inst)
            }

            let fadeSeconds = CMTimeGetSeconds(fade)
            captions.append(CaptionWindow(
                day: p.clip.day, label: p.clip.label, authorName: p.clip.authorName,
                captions: p.clip.captions,
                recordedAt: p.clip.recordedAt, emoji: p.clip.emoji, comments: p.clip.comments,
                start: isFirst ? CMTimeGetSeconds(p.start) : CMTimeGetSeconds(p.start) + fadeSeconds,
                end: isLast ? CMTimeGetSeconds(p.end) : CMTimeGetSeconds(p.end) - fadeSeconds,
                hasCameraStamp: p.clip.hasCameraStamp,
                captionFrame: p.clip.shownWhole))
        }

        var params: [Int: AVMutableAudioMixInputParameters] = [:]
        for (index, track) in audioTracks.enumerated() {
            if track.segments.isEmpty {
                composition.removeTrack(track)
            } else {
                params[index] = AVMutableAudioMixInputParameters(track: track)
            }
        }
        guard !params.isEmpty else { return }

        for (i, p) in placements.enumerated() {
            guard let track = params[p.trackIndex] else { continue }
            if i == 0 {
                track.setVolume(1, at: .zero)
            } else if fade > .zero {
                track.setVolumeRamp(
                    fromStartVolume: 0, toEndVolume: 1,
                    timeRange: CMTimeRange(start: p.start, duration: fade))
            } else {
                track.setVolume(1, at: p.start)
            }
            if i < placements.count - 1, fade > .zero {
                track.setVolumeRamp(
                    fromStartVolume: 1, toEndVolume: 0,
                    timeRange: CMTimeRange(start: placements[i + 1].start, duration: fade))
            }
        }
        audioParams.append(contentsOf: params.values)
    }


    enum SequentialFraming: Equatable {
        case fill
        case fitOnBed(subject: CGRect)
    }

    static func sequentialFraming(orientedSize: CGSize, canvas: CGSize) -> SequentialFraming {
        guard orientedSize.width > 0, orientedSize.height > 0,
              !FriendsTogetherCompositor.coversByCropping(
                  oriented: orientedSize, cell: canvas)
        else { return .fill }
        let fit = min(canvas.width / orientedSize.width, canvas.height / orientedSize.height)
        return .fitOnBed(subject: FriendsTogetherCompositor.frame(
            of: orientedSize, scaledBy: fit,
            centredIn: CGRect(origin: .zero, size: canvas)))
    }

    private static func reframed(
        _ loaded: [LoadedClip], canvas: CGSize
    ) async throws -> (clips: [LoadedClip], scratch: [URL]) {
        var out: [LoadedClip] = []
        var scratch: [URL] = []
        for clip in loaded {
            guard case .fitOnBed(let subject) = sequentialFraming(
                orientedSize: clip.orientedSize, canvas: canvas)
            else {
                out.append(clip)
                continue
            }
            do {
                let url = try await bedCopy(of: clip, canvas: canvas)
                scratch.append(url)
                var copy = try await reloaded(clip, from: url)
                copy.shownWhole = subject
                out.append(copy)
            } catch is CancellationError {
                discard(scratch)
                throw CancellationError()
            } catch {
                print("[stitch] reframe failed for day \(clip.day): \(error)")
                out.append(clip)
            }
        }
        return (out, scratch)
    }

    private static func bedCopy(of clip: LoadedClip, canvas: CGSize) async throws -> URL {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw StitchError.compositionFailed }
        try video.insertTimeRange(clip.videoRange, of: clip.videoTrack, at: .zero)
        if let audio = clip.audioTrack,
           let track = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let duration = CMTimeMinimum(clip.audioRange.duration, clip.duration)
            try track.insertTimeRange(
                CMTimeRange(start: clip.audioRange.start, duration: duration),
                of: audio, at: .zero)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.customVideoCompositorClass = FriendsTogetherCompositor.self
        videoComposition.instructions = [FriendsTogetherInstruction(
            timeRange: CMTimeRange(start: .zero, duration: clip.duration),
            placements: [FriendsTogetherPlacement(
                trackID: video.trackID,
                cell: CGRect(origin: .zero, size: canvas),
                orientation: FriendsTogetherPlacement.orientation(
                    for: clip.preferredTransform))])]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reframed_\(UUID().uuidString).mov")
        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw StitchError.compositionFailed }
        export.outputURL = url
        export.outputFileType = .mov
        export.videoComposition = videoComposition
        try await VideoExportSession.run(export)
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw StitchError.exportFailed(export.error?.localizedDescription ?? "unknown")
        }
        return url
    }

    private static func reloaded(_ clip: LoadedClip, from url: URL) async throws -> LoadedClip {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first
        else { throw StitchError.compositionFailed }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        return LoadedClip(
            id: clip.id,
            day: clip.day, label: clip.label, authorName: clip.authorName,
            captions: clip.captions,
            recordedAt: clip.recordedAt,
            emoji: clip.emoji, comments: clip.comments,
            asset: asset,
            videoRange: try await video.load(.timeRange),
            videoTrack: video,
            audioTrack: audio,
            audioRange: audio == nil ? .zero : try await audio!.load(.timeRange),
            naturalSize: try await video.load(.naturalSize),
            preferredTransform: try await video.load(.preferredTransform),
            frameDuration: (try? await video.load(.minFrameDuration)) ?? .invalid,
            hasCameraStamp: clip.hasCameraStamp)
    }


    private static func buildFriendsTogether(
        loaded: [LoadedClip],
        into composition: AVMutableComposition,
        renderSize: CGSize,
        sourceAspect: CGFloat,
        freezeFrames: [String: Double] = [:],
        dayOrder: [Int]? = nil,
        startAt: CMTime,
        instructions: inout [any AVVideoCompositionInstructionProtocol],
        audioParams: inout [AVMutableAudioMixInputParameters],
        captions: inout [CaptionWindow],
        authorCaptions: inout [AuthorCaptionWindow]
    ) throws {
        let rank = Dictionary((dayOrder ?? []).enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let groups = Dictionary(grouping: loaded, by: \.day)
            .sorted { (rank[$0.key] ?? Int.max, $0.key) < (rank[$1.key] ?? Int.max, $1.key) }
        var cursor = startAt

        for (day, clips) in groups {
            guard let groupDuration = clips.map(\.duration).max(),
                  groupDuration > .zero else { continue }
            let end = CMTimeAdd(cursor, groupDuration)
            var placements: [FriendsTogetherPlacement] = []

            let (rows, columns) = grid(for: clips.count, sourceAspect: sourceAspect)
            func edge(_ step: Int, of count: Int, across total: CGFloat) -> CGFloat {
                (total * CGFloat(step) / CGFloat(count)).rounded()
            }
            let volume = max(Float(0.15), Float(0.8) / Float(clips.count))

            for (index, clip) in clips.enumerated() {
                guard let videoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid)
                else { throw StitchError.compositionFailed }

                let freezeAt = freezeFrames[clip.id]
                for segment in cellSegments(
                    videoRange: clip.videoRange, momentDuration: groupDuration,
                    freezeAt: freezeAt, frameDuration: clip.frameDuration) {
                    let at = CMTimeAdd(cursor, segment.offset)
                    try videoTrack.insertTimeRange(
                        segment.source, of: clip.videoTrack, at: at)
                    if segment.duration != segment.source.duration {
                        videoTrack.scaleTimeRange(
                            CMTimeRange(start: at, duration: segment.source.duration),
                            toDuration: segment.duration)
                    }
                }

                let row = index / columns
                let column = index % columns
                let left = edge(column, of: columns, across: renderSize.width)
                let top = edge(row, of: rows, across: renderSize.height)
                let cell = CGRect(
                    x: left,
                    y: top,
                    width: edge(column + 1, of: columns, across: renderSize.width) - left,
                    height: edge(row + 1, of: rows, across: renderSize.height) - top)
                placements.append(FriendsTogetherPlacement(
                    trackID: videoTrack.trackID,
                    cell: cell,
                    orientation: FriendsTogetherPlacement.orientation(
                        for: clip.preferredTransform)))

                for caption in clip.captions {
                    guard let words = caption.trimmedText else { continue }
                    authorCaptions.append(AuthorCaptionWindow(
                        text: words, sticker: caption.placed, cell: cell,
                        start: CMTimeGetSeconds(cursor), end: CMTimeGetSeconds(end)))
                }

                if freezeAt == nil,
                   let audio = clip.audioTrack,
                   let audioTrack = composition.addMutableTrack(
                       withMediaType: .audio,
                       preferredTrackID: kCMPersistentTrackID_Invalid) {
                    var audioCursor = cursor
                    while audioCursor < end {
                        let duration = CMTimeMinimum(
                            clip.audioRange.duration,
                            CMTimeSubtract(end, audioCursor))
                        guard duration > .zero else { break }
                        try audioTrack.insertTimeRange(
                            CMTimeRange(start: clip.audioRange.start, duration: duration),
                            of: audio,
                            at: audioCursor)
                        audioCursor = CMTimeAdd(audioCursor, duration)
                    }
                    let params = AVMutableAudioMixInputParameters(track: audioTrack)
                    params.setVolume(volume, at: cursor)
                    audioParams.append(params)
                }
            }

            instructions.append(FriendsTogetherInstruction(
                timeRange: CMTimeRange(start: cursor, end: end),
                placements: placements))
            captions.append(CaptionWindow(
                day: day,
                label: clips.first?.label,
                authorName: nil,
                captions: [],
                recordedAt: clips.compactMap(\.recordedAt).max(),
                emoji: clips.flatMap(\.emoji),
                comments: clips.flatMap(\.comments),
                start: CMTimeGetSeconds(cursor),
                end: CMTimeGetSeconds(end)))
            cursor = end
        }
    }

    struct CellSegment: Equatable {
        let source: CMTimeRange
        let offset: CMTime
        let duration: CMTime
    }

    static func cellSegments(
        videoRange: CMTimeRange,
        momentDuration: CMTime,
        freezeAt: Double?,
        frameDuration: CMTime
    ) -> [CellSegment] {
        guard videoRange.duration > .zero, momentDuration > .zero else { return [] }

        if let freezeAt {
            let fallback = CMTime(value: 1, timescale: 30)
            let oneFrame = CMTimeMinimum(
                frameDuration.isValid && frameDuration > .zero ? frameDuration : fallback,
                videoRange.duration)
            let latest = CMTimeSubtract(videoRange.duration, oneFrame)
            let wanted = CMTime(seconds: max(freezeAt, 0), preferredTimescale: 600)
            let into = CMTimeClampToRange(
                wanted, range: CMTimeRange(start: .zero, duration: latest))
            return [CellSegment(
                source: CMTimeRange(
                    start: CMTimeAdd(videoRange.start, into), duration: oneFrame),
                offset: .zero,
                duration: momentDuration)]
        }

        var segments: [CellSegment] = []
        var offset = CMTime.zero
        while offset < momentDuration {
            let duration = CMTimeMinimum(
                videoRange.duration, CMTimeSubtract(momentDuration, offset))
            segments.append(CellSegment(
                source: CMTimeRange(start: videoRange.start, duration: duration),
                offset: offset,
                duration: duration))
            offset = CMTimeAdd(offset, duration)
        }
        return segments
    }

    static func kept(_ clips: [DayClip], ids: Set<String>?) -> [DayClip] {
        guard let ids else { return clips }
        return clips.filter { ids.contains($0.id) }
    }


    private static func fillTransform(for clip: LoadedClip, into rect: CGRect) -> CGAffineTransform {
        let r = CGRect(origin: .zero, size: clip.naturalSize).applying(clip.preferredTransform)
        var transform = clip.preferredTransform.concatenating(
            CGAffineTransform(translationX: -r.minX, y: -r.minY))
        let oriented = CGSize(width: abs(r.width), height: abs(r.height))
        let scale = max(rect.width / oriented.width, rect.height / oriented.height)
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let scaled = CGSize(width: oriented.width * scale, height: oriented.height * scale)
        transform = transform.concatenating(CGAffineTransform(
            translationX: rect.minX + (rect.width - scaled.width) / 2,
            y: rect.minY + (rect.height - scaled.height) / 2))
        return transform
    }

    static func grid(for count: Int, sourceAspect: CGFloat) -> (rows: Int, columns: Int) {
        guard count > 1 else { return (1, 1) }
        if count <= 3 {
            return sourceAspect < 1 ? (1, count) : (count, 1)
        }
        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        return (rows, columns)
    }

    private static let elongationLimit: CGFloat = 2

    static func mosaicRenderSize(
        count: Int, sourceAspect: CGFloat, longEdge: CGFloat
    ) -> CGSize {
        guard sourceAspect.isFinite, sourceAspect > 0, longEdge > 0 else {
            return CGSize(width: 2, height: 2)
        }
        let (rows, columns) = grid(for: max(count, 1), sourceAspect: sourceAspect)
        let mosaic = sourceAspect * CGFloat(columns) / CGFloat(rows)
        let ratio = mosaic > elongationLimit || mosaic < 1 / elongationLimit
            ? sourceAspect
            : mosaic
        let raw = ratio >= 1
            ? CGSize(width: longEdge, height: longEdge / ratio)
            : CGSize(width: longEdge * ratio, height: longEdge)
        return CGSize(
            width: max((raw.width / 2).rounded(.down) * 2, 2),
            height: max((raw.height / 2).rounded(.down) * 2, 2))
    }


    static func addTitleCard(
        _ card: TitleCard, to parentLayer: CALayer, renderSize: CGSize, duration: Double
    ) {
        let titleSize = renderSize.height * 0.05
        let subtitleSize = titleSize * 0.45

        func textLayer(_ string: String, size: CGFloat, weight: UIFont.Weight, alpha: CGFloat) -> (CATextLayer, CGSize) {
            let maxWidth = renderSize.width * 0.88
            var fontSize = size
            var attributed: NSAttributedString
            repeat {
                let base = UIFont.systemFont(ofSize: fontSize, weight: weight)
                let font = UIFont(
                    descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,
                    size: fontSize)
                attributed = NSAttributedString(string: string, attributes: [
                    .font: font,
                    .foregroundColor: UIColor.white.withAlphaComponent(alpha),
                    .kern: fontSize * 0.04,
                ])
                if attributed.size().width <= maxWidth { break }
                fontSize *= 0.94
            } while fontSize > size * 0.4
            let layer = CATextLayer()
            layer.string = attributed
            layer.alignmentMode = .center
            layer.contentsScale = 2
            return (layer, attributed.size())
        }

        let (title, titleTextSize) = textLayer(card.title, size: titleSize, weight: .heavy, alpha: 1)

        var layers: [CALayer] = [title]
        if let mark = mascotLayer(
            size: renderSize.height * 0.115,
            centredIn: renderSize,
            y: renderSize.height * 0.52 + titleTextSize.height * 1.9
        ) {
            layers.append(mark)
        }
        title.frame = CGRect(
            x: 0, y: renderSize.height * 0.52,
            width: renderSize.width, height: titleTextSize.height * 1.2)

        let (subtitle, subTextSize) = textLayer(card.subtitle, size: subtitleSize, weight: .semibold, alpha: 0.75)
        subtitle.frame = CGRect(
            x: 0, y: renderSize.height * 0.52 - subTextSize.height * 1.6,
            width: renderSize.width, height: subTextSize.height * 1.2)

        layers.append(subtitle)
        for layer in layers {
            layer.opacity = 0
            let anim = CAKeyframeAnimation(keyPath: "opacity")
            anim.values = [0, 1, 1, 0]
            let edge = min(0.35 / duration, 0.2)
            anim.keyTimes = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
            anim.beginTime = AVCoreAnimationBeginTimeAtZero
            anim.duration = duration
            anim.isRemovedOnCompletion = false
            anim.fillMode = .both
            layer.add(anim, forKey: "titleWindow")
            parentLayer.addSublayer(layer)
        }
    }

    private static func captionLayer(
        text: String, sticker: CaptionSticker, in frame: CGRect, renderSize: CGSize
    ) -> CALayer {
        let minEdge = min(frame.width, frame.height)
        let maxWidth = frame.width * 0.76
        let plate = sticker.style.plate
        let banded = plate != nil
        var fontSize = minEdge * (sticker.style == .headline ? 0.092 : 0.062) * sticker.scale
        let weight: UIFont.Weight = sticker.style == .headline ? .heavy : .bold
        let ink = sticker.tint.uiColor
        var attributed = NSAttributedString()
        repeat {
            attributed = NSAttributedString(string: text, attributes: [
                .font: roundedFont(size: fontSize, weight: weight),
                .foregroundColor: ink,
            ])
            let plateWidth = (plate?.padH ?? 0) * 2 * fontSize
            if attributed.size().width + plateWidth <= maxWidth { break }
            fontSize *= 0.92
        } while fontSize > 10

        let textSize = attributed.size()
        let padH = (plate?.padH ?? 0) * fontSize
        let padV = (plate?.padV ?? 0) * fontSize
        let box = CGSize(
            width: min(textSize.width, maxWidth) + padH * 2,
            height: textSize.height + padV * 2)

        let inset = frame.width * 0.03
        let lower = frame.minX + inset
        let upper = max(lower, frame.maxX - inset - box.width)
        let x = min(max(frame.minX + frame.width * sticker.x - box.width / 2, lower), upper)
        let yFromTop = frame.minY + frame.height * sticker.y
        let container = CALayer()
        container.frame = CGRect(
            x: x, y: renderSize.height - yFromTop - box.height / 2,
            width: box.width, height: box.height)
        if let plate, let fill = sticker.plateUIColor {
            container.backgroundColor = fill.cgColor
            container.cornerRadius = box.height * plate.radius
        }
        if sticker.angle != 0 {
            container.transform = CATransform3DMakeRotation(
                -sticker.angle * .pi / 180, 0, 0, 1)
        }

        let layer = CATextLayer()
        layer.string = attributed
        layer.alignmentMode = .center
        layer.truncationMode = .end
        layer.contentsScale = 2
        layer.frame = CGRect(
            x: padH, y: padV, width: box.width - padH * 2, height: textSize.height)
        if !banded {
            layer.shadowColor = UIColor.black.withAlphaComponent(0.32).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = max(fontSize * 0.08, 3)
            layer.shadowOffset = CGSize(width: 0, height: fontSize * 0.06)
        }
        container.addSublayer(layer)
        return container
    }

    private static func addAuthorCaption(
        _ caption: AuthorCaptionWindow, to parentLayer: CALayer, renderSize: CGSize
    ) {
        let pill = captionLayer(
            text: caption.text, sticker: caption.sticker,
            in: caption.cell, renderSize: renderSize)

        pill.opacity = 0
        let duration = max(caption.end - caption.start, 0.1)
        let edge = min(0.2 / duration, 0.15)
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 1, 1, 0]
        anim.keyTimes = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        anim.beginTime = caption.start <= 0 ? AVCoreAnimationBeginTimeAtZero : caption.start
        anim.duration = duration
        anim.isRemovedOnCompletion = false
        anim.fillMode = .both
        pill.add(anim, forKey: "authorCaption")

        parentLayer.addSublayer(pill)
    }

    private static func addCaption(
        _ caption: CaptionWindow, to parentLayer: CALayer, renderSize: CGSize,
        showAuthorMark: Bool
    ) {
        let label = caption.label?.uppercased() ?? "DAY \(caption.day)"
        let maxWidth = renderSize.width * 0.82
        var fontSize = renderSize.height * 0.036
        var attributed: NSAttributedString
        repeat {
            let baseFont = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
            let font = UIFont(
                descriptor: baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor,
                size: fontSize)
            attributed = NSAttributedString(string: label, attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .kern: fontSize * 0.08,
            ])
            let padH = fontSize * 0.95
            if attributed.size().width + padH * 2 <= maxWidth { break }
            fontSize *= 0.92
        } while fontSize > 9
        let textSize = attributed.size()

        let padH = fontSize * 0.95
        let padV = fontSize * 0.45
        let pillSize = CGSize(width: textSize.width + padH * 2, height: textSize.height + padV * 2)

        let pillOrigin = CGPoint(
            x: (renderSize.width - pillSize.width) / 2,
            y: renderSize.height * 0.075)

        let pill = CALayer()
        pill.frame = CGRect(origin: pillOrigin, size: pillSize)
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.45).cgColor
        pill.cornerRadius = pillSize.height / 2

        let text = CATextLayer()
        text.string = attributed
        text.alignmentMode = .center
        text.contentsScale = 2
        text.frame = CGRect(
            x: 0, y: (pillSize.height - textSize.height) / 2,
            width: pillSize.width, height: textSize.height)
        pill.addSublayer(text)

        pill.opacity = 0
        let duration = max(caption.end - caption.start, 0.1)
        let edge = min(0.2 / duration, 0.15)
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 1, 1, 0]
        anim.keyTimes = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        anim.beginTime = caption.start <= 0 ? AVCoreAnimationBeginTimeAtZero : caption.start
        anim.duration = duration
        anim.isRemovedOnCompletion = false
        anim.fillMode = .both
        pill.add(anim, forKey: "captionWindow")

        parentLayer.addSublayer(pill)
        addStampDecor(
            for: caption,
            to: parentLayer,
            renderSize: renderSize,
            duration: duration,
            edge: edge,
            showAuthorMark: showAuthorMark)
        addOverlayText(
            for: caption,
            to: parentLayer,
            renderSize: renderSize,
            duration: duration,
            edge: edge)
        addEmojiStickers(
            for: caption,
            to: parentLayer,
            renderSize: renderSize,
            duration: duration,
            edge: edge)
        addCommentBubbles(
            for: caption,
            to: parentLayer,
            renderSize: renderSize,
            duration: duration,
            edge: edge)
    }

    private static func addEmojiStickers(
        for caption: CaptionWindow,
        to parentLayer: CALayer,
        renderSize: CGSize,
        duration: Double,
        edge: Double
    ) {
        var seen = Set<String>()
        let emoji = caption.emoji.filter { seen.insert($0).inserted }.prefix(5)
        guard !emoji.isEmpty else { return }

        let target = CGRect(origin: .zero, size: renderSize)
        let minEdge = min(target.width, target.height)
        let size = max(minEdge * 0.11, 26)
        let spacing = size * 1.15
        let leftX = target.minX + minEdge * 0.07
        let baseY = renderSize.height - target.maxY + target.height * 0.28

        for (i, glyph) in emoji.enumerated() {
            let layer = CATextLayer()
            layer.string = NSAttributedString(string: glyph, attributes: [
                .font: UIFont.systemFont(ofSize: size * 0.82),
            ])
            layer.alignmentMode = .center
            layer.contentsScale = 2
            layer.frame = CGRect(
                x: leftX,
                y: baseY + CGFloat(i) * spacing,
                width: size, height: size)

            let stagger = min(Double(i) * 0.12, max(duration - 0.4, 0))
            let begin = caption.start <= 0
                ? AVCoreAnimationBeginTimeAtZero + stagger
                : caption.start + stagger
            let life = max(duration - stagger, 0.2)

            layer.opacity = 0
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            let e = min(0.18 / life, 0.2)
            fade.keyTimes = [0, NSNumber(value: e), NSNumber(value: 1 - edge), 1]
            fade.beginTime = begin
            fade.duration = life
            fade.isRemovedOnCompletion = false
            fade.fillMode = .both
            layer.add(fade, forKey: "emojiFade")

            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.2, 1.18, 1.0]
            pop.keyTimes = [0, 0.6, 1]
            pop.duration = min(0.35, life)
            pop.beginTime = begin
            pop.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
            ]
            pop.isRemovedOnCompletion = false
            pop.fillMode = .both
            layer.add(pop, forKey: "emojiPop")

            parentLayer.addSublayer(layer)
        }
    }

    private static func addCommentBubbles(
        for caption: CaptionWindow,
        to parentLayer: CALayer,
        renderSize: CGSize,
        duration: Double,
        edge: Double
    ) {
        let lines = Array(caption.comments.suffix(3))
        guard !lines.isEmpty else { return }

        let minEdge = min(renderSize.width, renderSize.height)
        let fontSize = max(minEdge * 0.026, 11)
        let padH = fontSize * 0.8
        let padV = fontSize * 0.45
        let spacing = fontSize * 0.5
        let leftX = renderSize.width * 0.045
        let maxWidth = renderSize.width * 0.62

        var y = renderSize.height * 0.028 + fontSize * 1.6

        for (i, line) in lines.enumerated() {
            var size = fontSize
            var attributed: NSAttributedString
            repeat {
                attributed = NSAttributedString(string: line, attributes: [
                    .font: roundedFont(size: size, weight: .semibold),
                    .foregroundColor: UIColor.white,
                ])
                if attributed.size().width + padH * 2 <= maxWidth { break }
                size *= 0.92
            } while size > 8
            let textSize = attributed.size()
            let bubbleSize = CGSize(
                width: textSize.width + padH * 2,
                height: textSize.height + padV * 2)

            let bubble = CALayer()
            bubble.frame = CGRect(x: leftX, y: y, width: bubbleSize.width, height: bubbleSize.height)
            bubble.backgroundColor = UIColor.black.withAlphaComponent(0.38).cgColor
            bubble.cornerRadius = bubbleSize.height / 2

            let text = CATextLayer()
            text.string = attributed
            text.alignmentMode = .center
            text.contentsScale = 2
            text.frame = CGRect(
                x: 0, y: (bubbleSize.height - textSize.height) / 2,
                width: bubbleSize.width, height: textSize.height)
            bubble.addSublayer(text)

            let stagger = min(Double(i) * 0.25, max(duration - 0.5, 0))
            let begin = caption.start <= 0
                ? AVCoreAnimationBeginTimeAtZero + stagger
                : caption.start + stagger
            let life = max(duration - stagger, 0.2)

            bubble.opacity = 0
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            let e = min(0.18 / life, 0.2)
            fade.keyTimes = [0, NSNumber(value: e), NSNumber(value: 1 - edge), 1]
            fade.beginTime = begin
            fade.duration = life
            fade.isRemovedOnCompletion = false
            fade.fillMode = .both
            bubble.add(fade, forKey: "commentFade")

            parentLayer.addSublayer(bubble)
            y += bubbleSize.height + spacing
        }
    }

    private static func addOverlayText(
        for caption: CaptionWindow,
        to parentLayer: CALayer,
        renderSize: CGSize,
        duration: Double,
        edge: Double
    ) {
        for line in caption.captions {
            guard let rawText = line.trimmedText else { continue }

            let text = captionLayer(
                text: rawText, sticker: line.placed,
                in: caption.captionFrame ?? CGRect(origin: .zero, size: renderSize),
                renderSize: renderSize)

            addCaptionFade(text, for: caption, duration: duration, edge: edge)
            parentLayer.addSublayer(text)
        }
    }

    private static func addCaptionFade(
        _ text: CALayer, for caption: CaptionWindow, duration: Double, edge: Double
    ) {
        text.opacity = 0
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 1, 1, 0]
        anim.keyTimes = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        anim.beginTime = caption.start <= 0 ? AVCoreAnimationBeginTimeAtZero : caption.start
        anim.duration = duration
        anim.isRemovedOnCompletion = false
        anim.fillMode = .both
        text.add(anim, forKey: "overlayTextWindow")
    }

    private static func addStampDecor(
        for caption: CaptionWindow,
        to parentLayer: CALayer,
        renderSize: CGSize,
        duration: Double,
        edge: Double,
        showAuthorMark: Bool
    ) {
        guard showAuthorMark else {
            if caption.hasCameraStamp { return }
            addTimestampPill(
                for: caption, to: parentLayer, renderSize: renderSize,
                duration: duration, edge: edge)
            return
        }

        let identityColor = Identity.uiColor(for: caption.authorName)
        let target = CGRect(origin: .zero, size: renderSize)
        let minEdge = min(target.width, target.height)
        let stampWidth = max(minEdge * 0.34, 118)
        let stampHeight = stampWidth * 0.33

        let origin = CGPoint(
            x: renderSize.width - stampWidth - renderSize.width * 0.075,
            y: renderSize.height - stampHeight - renderSize.height * 0.075)

        let group = CALayer()
        group.frame = CGRect(origin: origin, size: CGSize(width: stampWidth, height: stampHeight))

        let backing = CALayer()
        backing.frame = group.bounds
        backing.cornerRadius = stampHeight / 2
        backing.backgroundColor = UIColor.black.withAlphaComponent(0.36).cgColor
        backing.borderColor = identityColor.withAlphaComponent(0.95).cgColor
        backing.borderWidth = max(stampHeight * 0.035, 1.5)
        group.addSublayer(backing)

        let markSize = stampHeight * 0.72
        let mark = CALayer()
        mark.frame = CGRect(
            x: stampHeight * 0.14,
            y: (stampHeight - markSize) / 2,
            width: markSize,
            height: markSize)
        mark.cornerRadius = markSize / 2
        mark.backgroundColor = UIColor.white.cgColor
        mark.borderColor = identityColor.cgColor
        mark.borderWidth = max(markSize * 0.06, 2)
        group.addSublayer(mark)

        if let authorName = caption.authorName, !authorName.isEmpty {
            let markText = CATextLayer()
            let markFontSize = markSize * 0.38
            markText.string = NSAttributedString(string: Identity.initial(for: authorName), attributes: [
                .font: roundedFont(size: markFontSize, weight: .black),
                .foregroundColor: UIColor.black,
            ])
            markText.alignmentMode = .center
            markText.contentsScale = 2
            markText.frame = CGRect(
                x: mark.frame.minX,
                y: mark.frame.minY + (markSize - markFontSize * 1.25) / 2,
                width: markSize,
                height: markFontSize * 1.25)
            group.addSublayer(markText)
        } else if let mascot = UIImage(named: "OneDayMascot")?.cgImage {
            mark.contents = mascot
            mark.contentsGravity = .resizeAspectFill
            mark.contentsScale = 2
            mark.masksToBounds = true
        }

        let dateText = formattedStampDate(caption.recordedAt)
        let timeText = formattedStampTime(caption.recordedAt)
        let textX = mark.frame.maxX + stampWidth * 0.055
        let textWidth = stampWidth - textX - stampHeight * 0.18

        let date = CATextLayer()
        let dateFontSize = stampHeight * 0.2
        date.string = NSAttributedString(string: dateText.uppercased(), attributes: [
            .font: roundedFont(size: dateFontSize, weight: .heavy),
            .foregroundColor: UIColor.white.withAlphaComponent(0.82),
            .kern: dateFontSize * 0.05,
        ])
        date.contentsScale = 2
        date.frame = CGRect(
            x: textX,
            y: stampHeight * 0.51,
            width: textWidth,
            height: dateFontSize * 1.25)
        group.addSublayer(date)

        let time = CATextLayer()
        let timeFontSize = stampHeight * 0.28
        time.string = NSAttributedString(string: timeText, attributes: [
            .font: roundedFont(size: timeFontSize, weight: .black),
            .foregroundColor: UIColor.white,
        ])
        time.contentsScale = 2
        time.frame = CGRect(
            x: textX,
            y: stampHeight * 0.18,
            width: textWidth,
            height: timeFontSize * 1.25)
        group.addSublayer(time)

        group.opacity = 0
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 1, 1, 0]
        anim.keyTimes = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        anim.beginTime = caption.start <= 0 ? AVCoreAnimationBeginTimeAtZero : caption.start
        anim.duration = duration
        anim.isRemovedOnCompletion = false
        anim.fillMode = .both
        group.add(anim, forKey: "stickerWindow")

        parentLayer.addSublayer(group)
    }

    private static func addTimestampPill(
        for caption: CaptionWindow,
        to parentLayer: CALayer,
        renderSize: CGSize,
        duration: Double,
        edge: Double
    ) {
        let target = CGRect(origin: .zero, size: renderSize)
        let minEdge = min(target.width, target.height)

        let text = "\(formattedStampDateShort(caption.recordedAt))  ·  \(formattedStampTime(caption.recordedAt))"
        let fontSize = max(minEdge * 0.032, 12)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: roundedFont(size: fontSize, weight: .heavy),
            .foregroundColor: UIColor.white,
            .kern: fontSize * 0.02,
        ])
        let textSize = attributed.size()
        let padH = fontSize * 0.72
        let padV = fontSize * 0.42
        let pillSize = CGSize(width: textSize.width + padH * 2, height: textSize.height + padV * 2)

        let origin = CGPoint(
            x: renderSize.width - pillSize.width - renderSize.width * 0.06,
            y: renderSize.height - pillSize.height - renderSize.height * 0.06)

        let pill = CALayer()
        pill.frame = CGRect(origin: origin, size: pillSize)
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.32).cgColor
        pill.cornerRadius = pillSize.height / 2

        let textLayer = CATextLayer()
        textLayer.string = attributed
        textLayer.alignmentMode = .center
        textLayer.contentsScale = 2
        textLayer.frame = CGRect(
            x: 0, y: (pillSize.height - textSize.height) / 2,
            width: pillSize.width, height: textSize.height)
        pill.addSublayer(textLayer)

        pill.opacity = 0
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 1, 1, 0]
        anim.keyTimes = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        anim.beginTime = caption.start <= 0 ? AVCoreAnimationBeginTimeAtZero : caption.start
        anim.duration = duration
        anim.isRemovedOnCompletion = false
        anim.fillMode = .both
        pill.add(anim, forKey: "timestampWindow")

        parentLayer.addSublayer(pill)
    }

    private static func mascotLayer(
        size: CGFloat, centredIn renderSize: CGSize, y: CGFloat
    ) -> CALayer? {
        guard let image = UIImage(named: "OneDayMascot")?.cgImage else { return nil }
        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resizeAspect
        layer.frame = CGRect(
            x: (renderSize.width - size) / 2, y: y, width: size, height: size)
        return layer
    }

    static func addWatermark(to parentLayer: CALayer, renderSize: CGSize) {
        let fontSize = max(renderSize.height * 0.016, 11)
        let attributed = NSAttributedString(string: "1Day", attributes: [
            .font: roundedFont(size: fontSize, weight: .heavy),
            .foregroundColor: UIColor.white.withAlphaComponent(0.62),
            .kern: fontSize * 0.04,
        ])
        let textSize = attributed.size()
        let left = renderSize.width * 0.045
        let bottom = renderSize.height * 0.028
        if let mascot = UIImage(named: "OneDayMascot")?.cgImage {
            let glyph = fontSize * 1.7
            let layer = CALayer()
            layer.contents = mascot
            layer.contentsGravity = .resizeAspect
            layer.opacity = 0.82
            layer.frame = CGRect(
                x: left, y: bottom - (glyph - textSize.height) / 2,
                width: glyph, height: glyph)
            parentLayer.addSublayer(layer)
        }
        let layer = CATextLayer()
        layer.string = attributed
        layer.contentsScale = 2
        layer.frame = CGRect(
            x: left + fontSize * 2.1,
            y: bottom,
            width: textSize.width, height: textSize.height)
        parentLayer.addSublayer(layer)
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return UIFont(
            descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,
            size: size)
    }

    private static func formattedStampDate(_ date: Date?) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.effective.locale
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date ?? .now)
    }

    private static func formattedStampDateShort(_ date: Date?) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.effective.locale
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date ?? .now)
    }

    private static func formattedStampTime(_ date: Date?) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.effective.locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date ?? .now)
    }

}
