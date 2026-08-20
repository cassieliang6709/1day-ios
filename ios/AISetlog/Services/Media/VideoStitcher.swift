import AVFoundation
import UIKit

/// Stitches the daily clips into one short diary film, entirely on-device.
///
/// Features:
/// - sequential layout with crossfade cuts
/// - optional opening title card (challenge name + date range)
/// - "DAY N" captions burned in via AVVideoCompositionCoreAnimationTool
///
/// Simulator note: CoreAnimationTool overlays (captions + title card) crash
/// the simulator's software render path, so they are device-only.
enum VideoStitcher {

    enum Layout {
        case sequential
        /// Shared-room clips are grouped by moment, with every friend shown
        /// simultaneously before advancing to the next moment.
        case friendsTogether
    }

    struct TitleCard {
        let title: String
        let subtitle: String
    }

    /// The shape of the finished film.
    ///
    /// A property of the *film*, not of each clip: you choose it (and change
    /// it) after the day is filmed. Clips that don't match get letterboxed
    /// rather than cropped — the whole point of the app is keeping what you
    /// captured, so it never throws pixels away to make a frame fit.
    enum Aspect: String, CaseIterable, Identifiable {
        case portrait, landscape, square

        var id: String { rawValue }

        /// width / height
        var ratio: CGFloat {
            switch self {
            case .portrait: 9.0 / 16.0
            case .landscape: 16.0 / 9.0
            case .square: 1
            }
        }

        /// Render size for a film whose source clips have this long edge.
        /// All three land on the same short edge, so switching aspect doesn't
        /// change how heavy the export is.
        func renderSize(sourceLongEdge: CGFloat) -> CGSize {
            let short = (sourceLongEdge * 9 / 16).rounded()
            let long = sourceLongEdge.rounded()
            let raw: CGSize = switch self {
            case .portrait: CGSize(width: short, height: long)
            case .landscape: CGSize(width: long, height: short)
            case .square: CGSize(width: short, height: short)
            }
            // H.264 wants even dimensions.
            return CGSize(
                width: (raw.width / 2).rounded(.down) * 2,
                height: (raw.height / 2).rounded(.down) * 2)
        }
    }

    struct Options {
        var crossfadeSeconds: Double = 0.35
        var showDayCaptions = true
        var layout: Layout = .sequential
        var titleCard: TitleCard?
        var titleSeconds: Double = 2.2
        /// nil keeps the film in the shape of its first clip — the behaviour
        /// from before aspect became a choice.
        var aspect: Aspect?
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
        let day: Int
        let label: String?
        let authorName: String?
        let overlayText: String?
        let recordedAt: Date?
        let emoji: [String]
        let comments: [String]
        /// Kept alive on purpose: AVAssetTrack does NOT retain its parent
        /// asset, and insertTimeRange fails (-12780) on a track whose asset
        /// has been deallocated.
        let asset: AVURLAsset
        let videoRange: CMTimeRange
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let audioRange: CMTimeRange
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform

        var duration: CMTime { videoRange.duration }

        var orientedSize: CGSize {
            let r = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            return CGSize(width: abs(r.width), height: abs(r.height))
        }
    }

    /// A caption to draw later: which day, over which time window.
    private struct CaptionWindow {
        let day: Int
        let label: String?
        let authorName: String?
        let overlayText: String?
        let recordedAt: Date?
        let emoji: [String]
        let comments: [String]
        let start: Double
        let end: Double
    }

    // MARK: - Entry point

    static func stitch(clips: [DayClip], options: Options = .default) async throws -> URL {
        guard !clips.isEmpty else { throw StitchError.noClips }

        #if !targetEnvironment(simulator)
        let drawCaptions = options.showDayCaptions
        let titleCard = options.titleCard
        #endif

        // ---- Load track info for every clip --------------------------------
        var loaded: [LoadedClip] = []
        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            guard let video = try await asset.loadTracks(withMediaType: .video).first else { continue }
            // Use each track's own timeRange, NOT the container duration —
            // AAC audio is usually a few ms shorter than the video, and
            // inserting past a source track's end throws.
            let videoRange = try await video.load(.timeRange)
            let naturalSize = try await video.load(.naturalSize)
            let transform = try await video.load(.preferredTransform)
            let audio = try await asset.loadTracks(withMediaType: .audio).first
            let audioRange = audio == nil ? CMTimeRange.zero : try await audio!.load(.timeRange)
            loaded.append(LoadedClip(
                day: clip.day, label: clip.label, authorName: clip.authorName,
                overlayText: clip.overlayText,
                recordedAt: clip.recordedAt,
                emoji: clip.emoji, comments: clip.comments,
                asset: asset, videoRange: videoRange, videoTrack: video,
                audioTrack: audio, audioRange: audioRange,
                naturalSize: naturalSize, preferredTransform: transform))
        }
        guard !loaded.isEmpty else { throw StitchError.noClips }

        let firstSize = loaded[0].orientedSize
        let renderSize = CGSize(
            width: (firstSize.width / 2).rounded(.down) * 2,
            height: (firstSize.height / 2).rounded(.down) * 2)

        #if targetEnvironment(simulator)
        let titleOffset = CMTime.zero
        #else
        let titleOffset = titleCard == nil
            ? CMTime.zero
            : CMTime(seconds: options.titleSeconds, preferredTimescale: 600)
        #endif

        // ---- Build the track layout ----------------------------------------
        let composition = AVMutableComposition()
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var audioParams: [AVMutableAudioMixInputParameters] = []
        var captions: [CaptionWindow] = []

        switch options.layout {
        case .sequential:
            try buildSequential(
                loaded: loaded, into: composition, renderSize: renderSize,
                crossfadeSeconds: options.crossfadeSeconds, startAt: titleOffset,
                instructions: &instructions, audioParams: &audioParams, captions: &captions)
        case .friendsTogether:
            try buildFriendsTogether(
                loaded: loaded, into: composition, renderSize: renderSize,
                startAt: titleOffset, instructions: &instructions,
                audioParams: &audioParams, captions: &captions)
        }

        // ---- Title card: a source-less black segment up front ---------------
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

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParams

        // ---- Overlays: title card text + DAY N captions + watermark ---------
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
                // Solo diaries don't need a "who filmed this" avatar — it's
                // always you. Only the multi-friend room finale earns one.
                let multiAuthor = Set(
                    loaded.compactMap { $0.authorName?.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                ).count > 1
                for caption in captions {
                    addCaption(caption, to: parentLayer, renderSize: renderSize, showAuthorMark: multiAuthor)
                }
            }
            addWatermark(to: parentLayer, renderSize: renderSize)

            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        }
        #endif

        // ---- Export ----------------------------------------------------------
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
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        guard export.status == .completed else {
            print("[stitch] export status=\(export.status.rawValue) error=\(String(describing: export.error))")
            throw StitchError.exportFailed(export.error?.localizedDescription ?? "unknown")
        }
        return outURL
    }

    // MARK: - Sequential layout (crossfades)

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
        instructions: inout [AVMutableVideoCompositionInstruction],
        audioParams: inout [AVMutableAudioMixInputParameters],
        captions: inout [CaptionWindow]
    ) throws {
        // Fade can't be longer than half the shortest clip.
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
                overlayText: p.clip.overlayText,
                recordedAt: p.clip.recordedAt, emoji: p.clip.emoji, comments: p.clip.comments,
                start: isFirst ? CMTimeGetSeconds(p.start) : CMTimeGetSeconds(p.start) + fadeSeconds,
                end: isLast ? CMTimeGetSeconds(p.end) : CMTimeGetSeconds(p.end) - fadeSeconds))
        }

        // Audio tracks are added up front but only filled for clips that have
        // sound. Any that stay empty — every clip filmed with the microphone
        // denied, say — must come back out: an empty audio track fails the
        // export with AVError -11838 instead of producing a silent film.
        //
        // Keyed by the original track index rather than compacted, because
        // placements refer to tracks by that index.
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

    // MARK: - Shared-room layout

    /// Plays each moment once, placing every friend's contribution for that
    /// moment side by side. Shorter takes loop until the longest take ends.
    private static func buildFriendsTogether(
        loaded: [LoadedClip],
        into composition: AVMutableComposition,
        renderSize: CGSize,
        startAt: CMTime,
        instructions: inout [AVMutableVideoCompositionInstruction],
        audioParams: inout [AVMutableAudioMixInputParameters],
        captions: inout [CaptionWindow]
    ) throws {
        let groups = Dictionary(grouping: loaded, by: \.day)
            .sorted { $0.key < $1.key }
        var cursor = startAt

        for (day, clips) in groups {
            guard let groupDuration = clips.map(\.duration).max(),
                  groupDuration > .zero else { continue }
            let end = CMTimeAdd(cursor, groupDuration)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, end: end)
            instruction.backgroundColor = UIColor.black.cgColor
            var layers: [AVMutableVideoCompositionLayerInstruction] = []

            let (rows, columns) = grid(for: clips.count, in: renderSize)
            let cellSize = CGSize(
                width: renderSize.width / CGFloat(columns),
                height: renderSize.height / CGFloat(rows))
            let gap = renderSize.width * 0.004
            let volume = max(Float(0.15), Float(0.8) / Float(clips.count))

            for (index, clip) in clips.enumerated() {
                guard let videoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid)
                else { throw StitchError.compositionFailed }

                var clipCursor = cursor
                while clipCursor < end {
                    let duration = CMTimeMinimum(
                        clip.videoRange.duration,
                        CMTimeSubtract(end, clipCursor))
                    try videoTrack.insertTimeRange(
                        CMTimeRange(start: clip.videoRange.start, duration: duration),
                        of: clip.videoTrack,
                        at: clipCursor)
                    clipCursor = CMTimeAdd(clipCursor, duration)
                }

                let row = index / columns
                let column = index % columns
                let cell = CGRect(
                    x: CGFloat(column) * cellSize.width,
                    y: CGFloat(row) * cellSize.height,
                    width: cellSize.width,
                    height: cellSize.height)
                    .insetBy(dx: gap, dy: gap)
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                let (transform, crop) = cellTransform(for: clip, into: cell)
                layer.setTransform(transform, at: cursor)
                layer.setCropRectangle(crop, at: cursor)
                layers.append(layer)

                if let audio = clip.audioTrack,
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

            instruction.layerInstructions = layers
            instructions.append(instruction)
            captions.append(CaptionWindow(
                day: day,
                label: clips.first?.label,
                authorName: nil,
                overlayText: nil,
                recordedAt: clips.compactMap(\.recordedAt).max(),
                emoji: clips.flatMap(\.emoji),
                comments: clips.flatMap(\.comments),
                start: CMTimeGetSeconds(cursor),
                end: CMTimeGetSeconds(end)))
            cursor = end
        }
    }

    // MARK: - Geometry

    /// Applies the clip's own rotation, then aspect-fills it into `rect`.
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

    /// Like fillTransform, but crops the source so nothing spills outside the
    /// cell (layer instructions do not clip). Returns the transform plus the
    /// crop rectangle in the source track's pre-transform coordinates.
    /// How a moment's clips share the frame when everyone filmed it.
    ///
    /// A square-ish grid put two people side by side, which in a portrait film
    /// crops each 9:16 clip to a sliver — heads clipped, nobody legible. Two or
    /// three people stack top to bottom instead, so each keeps the full width
    /// and the moment reads as a list of who was there. Past three, strips get
    /// too short to see and a grid is the better trade.
    static func grid(for count: Int, in renderSize: CGSize) -> (rows: Int, columns: Int) {
        guard count > 1 else { return (1, 1) }
        let isPortrait = renderSize.height >= renderSize.width
        if count <= 3 {
            return isPortrait ? (count, 1) : (1, count)
        }
        let side = Int(ceil(sqrt(Double(count))))
        let other = Int(ceil(Double(count) / Double(side)))
        return isPortrait ? (side, other) : (other, side)
    }

    private static func cellTransform(
        for clip: LoadedClip, into cell: CGRect
    ) -> (CGAffineTransform, CGRect) {
        let r = CGRect(origin: .zero, size: clip.naturalSize).applying(clip.preferredTransform)
        let normalize = clip.preferredTransform.concatenating(
            CGAffineTransform(translationX: -r.minX, y: -r.minY))
        let oriented = CGSize(width: abs(r.width), height: abs(r.height))

        // Centered crop with the cell's aspect ratio, in oriented space.
        let cellAspect = cell.width / cell.height
        var cropSize = oriented
        if oriented.width / oriented.height > cellAspect {
            cropSize.width = oriented.height * cellAspect
        } else {
            cropSize.height = oriented.width / cellAspect
        }
        let cropOrigin = CGPoint(
            x: (oriented.width - cropSize.width) / 2,
            y: (oriented.height - cropSize.height) / 2)
        let orientedCrop = CGRect(origin: cropOrigin, size: cropSize)

        let sourceCrop = orientedCrop.applying(normalize.inverted()).standardized

        let scale = cell.width / cropSize.width
        var transform = normalize
        transform = transform.concatenating(
            CGAffineTransform(translationX: -cropOrigin.x, y: -cropOrigin.y))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(
            CGAffineTransform(translationX: cell.minX, y: cell.minY))
        return (transform, sourceCrop)
    }

    // MARK: - Overlays (device only)

    private static func addTitleCard(
        _ card: TitleCard, to parentLayer: CALayer, renderSize: CGSize, duration: Double
    ) {
        let titleSize = renderSize.height * 0.05
        let subtitleSize = titleSize * 0.45

        // Shrink long titles until they fit (with side margins) instead of
        // letting CATextLayer clip them at the frame edges.
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

        // CA coordinates: origin bottom-left.
        let (title, titleTextSize) = textLayer(card.title, size: titleSize, weight: .heavy, alpha: 1)
        title.frame = CGRect(
            x: 0, y: renderSize.height * 0.52,
            width: renderSize.width, height: titleTextSize.height * 1.2)

        let (subtitle, subTextSize) = textLayer(card.subtitle, size: subtitleSize, weight: .semibold, alpha: 0.75)
        subtitle.frame = CGRect(
            x: 0, y: renderSize.height * 0.52 - subTextSize.height * 1.6,
            width: renderSize.width, height: subTextSize.height * 1.2)

        for layer in [title, subtitle] {
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

    /// A rounded "DAY N" pill at the bottom center, visible only during its
    /// time window.
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

        // CA coordinates: origin bottom-left.
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

    /// Floats the clip's emoji reactions up the left edge — each pops in with a
    /// little stagger so a reacted-on clip feels alive in the final film.
    private static func addEmojiStickers(
        for caption: CaptionWindow,
        to parentLayer: CALayer,
        renderSize: CGSize,
        duration: Double,
        edge: Double
    ) {
        // Distinct emoji, first-seen order, capped so they never crowd the frame.
        var seen = Set<String>()
        let emoji = caption.emoji.filter { seen.insert($0).inserted }.prefix(5)
        guard !emoji.isEmpty else { return }

        let target = CGRect(origin: .zero, size: renderSize)
        let minEdge = min(target.width, target.height)
        let size = max(minEdge * 0.11, 26)
        let spacing = size * 1.15
        let leftX = target.minX + minEdge * 0.07
        // CA coords (origin bottom-left): stack upward from the lower third.
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

            // Stagger each pop-in, but keep every glyph inside its clip's window.
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

    /// The latest few comments rise as little bubbles above the watermark —
    /// the friends' voices become part of the film, not just the app.
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

        // CA coordinates: origin bottom-left. Stack upward from just above
        // the watermark line.
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

            // Stagger each bubble's rise, keeping it inside the clip's window.
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
        guard let rawText = caption.overlayText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawText.isEmpty else { return }

        let target = CGRect(origin: .zero, size: renderSize)
        let maxWidth = target.width * 0.68
        var fontSize = min(target.width, target.height) * 0.062
        var attributed: NSAttributedString
        repeat {
            attributed = NSAttributedString(string: rawText, attributes: [
                .font: roundedFont(size: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
            ])
            if attributed.size().width <= maxWidth { break }
            fontSize *= 0.92
        } while fontSize > 10

        let textSize = attributed.size()
        let textLayerSize = CGSize(width: maxWidth, height: textSize.height * 1.18)

        let videoCenter = CGPoint(x: target.midX, y: target.minY + target.height * 0.43)
        let caOrigin = CGPoint(
            x: max(target.minX + target.width * 0.08, min(videoCenter.x - textLayerSize.width / 2, target.maxX - textLayerSize.width - target.width * 0.08)),
            y: renderSize.height - videoCenter.y - textLayerSize.height / 2)

        let text = CATextLayer()
        text.string = attributed
        text.alignmentMode = .center
        text.contentsScale = 2
        text.shadowColor = UIColor.black.withAlphaComponent(0.32).cgColor
        text.shadowOpacity = 1
        text.shadowRadius = max(fontSize * 0.08, 3)
        text.shadowOffset = CGSize(width: 0, height: fontSize * 0.06)
        text.frame = CGRect(origin: caOrigin, size: textLayerSize)

        text.opacity = 0
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 1, 1, 0]
        anim.keyTimes = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        anim.beginTime = caption.start <= 0 ? AVCoreAnimationBeginTimeAtZero : caption.start
        anim.duration = duration
        anim.isRemovedOnCompletion = false
        anim.fillMode = .both
        text.add(anim, forKey: "overlayTextWindow")

        parentLayer.addSublayer(text)
    }

    private static func addStampDecor(
        for caption: CaptionWindow,
        to parentLayer: CALayer,
        renderSize: CGSize,
        duration: Double,
        edge: Double,
        showAuthorMark: Bool
    ) {
        // Solo diaries: a clean, BeReal-style "date · time" pill — no avatar,
        // no colored ring, just a quiet timestamp for that real-moment feel.
        guard showAuthorMark else {
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

        let markText = CATextLayer()
        let markFontSize = markSize * 0.38
        markText.string = NSAttributedString(string: Identity.initial(for: caption.authorName), attributes: [
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

    /// A single quiet capsule — "Jul 24 · 2:30 PM" — pinned to the top-right,
    /// mirroring the avatar stamp's corner so solo and room films sit alike.
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

        // CA coordinates: origin bottom-left.
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

    /// A tiny "made with 1Day" tag in the bottom-left corner, present for the
    /// whole film — every shared vlog quietly advertises where it came from.
    private static func addWatermark(to parentLayer: CALayer, renderSize: CGSize) {
        let fontSize = max(renderSize.height * 0.016, 11)
        let attributed = NSAttributedString(string: "made with 1Day", attributes: [
            .font: roundedFont(size: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.55),
            .kern: fontSize * 0.04,
        ])
        let textSize = attributed.size()
        let layer = CATextLayer()
        layer.string = attributed
        layer.contentsScale = 2
        // CA coordinates: origin bottom-left.
        layer.frame = CGRect(
            x: renderSize.width * 0.045,
            y: renderSize.height * 0.028,
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
