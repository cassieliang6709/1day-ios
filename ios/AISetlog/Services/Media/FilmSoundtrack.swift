import AVFoundation
import Foundation

/// What a finished film sounds like: its own clips' sound, a music track, or
/// both with the clips turned down — plus an optional voiceover on top.
///
/// Runs after `VideoStitcher` on the film it made, so the stitcher stays about
/// pictures. The video is copied across untouched; only the audio is remixed.
enum FilmSoundtrack {
    enum Mode: String, CaseIterable, Identifiable {
        /// The clips' own sound only.
        case original
        /// Music only.
        case music
        /// Music, with the clips' sound kept underneath.
        case mix

        var id: String { rawValue }
    }

    /// A bundled track. The six shipped now are placeholders synthesized for
    /// development; licensed music replaces them before release.
    struct Track: Identifiable, Equatable {
        let id: String
        /// Moods this track suits. A track with none suits any day.
        let moods: [Mood]

        var url: URL? { Bundle.main.url(forResource: id, withExtension: "m4a") }
    }

    static let catalog: [Track] = [
        Track(id: "sunny", moods: [.happy]),
        Track(id: "spark", moods: [.happy, .angry]),
        Track(id: "breeze", moods: [.calm]),
        Track(id: "drift", moods: [.tired, .calm]),
        Track(id: "rain", moods: [.sad, .tired]),
        Track(id: "film", moods: []),
    ]

    /// Clips' sound under music in `.mix`: laughter and voices still come
    /// through, the two-second cuts in it don't.
    static let originalUnderMusic: Float = 0.3
    /// Everything else under a voiceover, so the person talking is on top.
    static let underVoiceover: Float = 0.35
    static let fadeOutSeconds = 1.0

    /// A track for the day's mood, skipping `current` so 换一首 always changes
    /// something. With no mood, any track.
    static func pick(for mood: Mood?, excluding current: Track? = nil) -> Track {
        let suited = catalog.filter { track in
            guard let mood else { return true }
            return track.moods.isEmpty || track.moods.contains(mood)
        }
        let pool = suited.filter { $0 != current }
        return pool.randomElement() ?? catalog.first { $0 != current } ?? catalog[0]
    }

    enum RenderError: Error { case noVideo, exportFailed }

    /// A new file with `film`'s pictures and the chosen sound. `.original`
    /// with no voiceover hands back `film` itself: there is nothing to remix.
    static func render(
        film: URL, mode: Mode, track: Track?, voiceover: URL?
    ) async throws -> URL {
        if mode == .original, voiceover == nil { return film }

        let source = AVURLAsset(url: film)
        guard let video = try await source.loadTracks(withMediaType: .video).first else {
            throw RenderError.noVideo
        }
        let duration = try await source.load(.duration)
        let whole = CMTimeRange(start: .zero, duration: duration)

        let composition = AVMutableComposition()
        guard let videoOut = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw RenderError.exportFailed }
        try videoOut.insertTimeRange(whole, of: video, at: .zero)
        videoOut.preferredTransform = try await video.load(.preferredTransform)

        var params: [AVMutableAudioMixInputParameters] = []
        let voiceDucking: Float = voiceover == nil ? 1 : underVoiceover

        if mode != .music, let audio = try await source.loadTracks(withMediaType: .audio).first,
           let out = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try out.insertTimeRange(whole, of: audio, at: .zero)
            let p = AVMutableAudioMixInputParameters(track: out)
            p.setVolume((mode == .mix ? originalUnderMusic : 1) * voiceDucking, at: .zero)
            params.append(p)
        }

        if mode != .original, let url = track?.url,
           let out = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try await loop(url, into: out, filling: duration)
            let p = AVMutableAudioMixInputParameters(track: out)
            let level = voiceDucking
            let fade = CMTime(seconds: min(fadeOutSeconds, duration.seconds / 2), preferredTimescale: 600)
            p.setVolume(level, at: .zero)
            p.setVolumeRamp(
                fromStartVolume: level, toEndVolume: 0,
                timeRange: CMTimeRange(start: duration - fade, duration: fade))
            params.append(p)
        }

        if let voiceover,
           let audio = try await AVURLAsset(url: voiceover).loadTracks(withMediaType: .audio).first,
           let out = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let length = try await audio.load(.timeRange).duration
            try out.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTimeMinimum(length, duration)), of: audio, at: .zero)
            params.append(AVMutableAudioMixInputParameters(track: out))
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = params

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("film_sound_\(UUID().uuidString).mp4")
        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw RenderError.exportFailed }
        export.outputURL = outURL
        export.outputFileType = .mp4
        export.audioMix = mix
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        guard export.status == .completed else {
            print("[soundtrack] export failed: \(String(describing: export.error))")
            throw RenderError.exportFailed
        }
        return outURL
    }

    /// The music laid end to end until the film is covered, the last pass cut short.
    private static func loop(_ url: URL, into track: AVMutableCompositionTrack, filling duration: CMTime) async throws {
        let asset = AVURLAsset(url: url)
        guard let audio = try await asset.loadTracks(withMediaType: .audio).first else { return }
        let length = try await audio.load(.timeRange).duration
        guard length > .zero else { return }
        var cursor = CMTime.zero
        while cursor < duration {
            let piece = CMTimeMinimum(length, duration - cursor)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: piece), of: audio, at: cursor)
            cursor = cursor + piece
        }
    }
}
