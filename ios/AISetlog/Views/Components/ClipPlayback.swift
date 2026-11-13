import SwiftUI
import AVFoundation

/// Endlessly looping muted-free playback of one clip. Fills its frame like
/// the live camera preview does (`.resizeAspectFill`) — SwiftUI's `VideoPlayer`
/// aspect-*fits* by default, which is what was letterboxing recorded clips
/// with black bars whenever the footage didn't exactly match the frame.
struct LoopingClipPlayer: View {
    let url: URL
    /// Bump this (e.g. the card's `recordedAt`) when the file at `url` gets
    /// overwritten in place — a re-record reuses the same file name, which
    /// AVPlayer can't notice on its own.
    var refreshToken: Date? = nil
    /// Applied as the frames come off the file. Nothing is written anywhere, so
    /// turning it off gives back exactly what the camera saw.
    var look: PersonalEffectParameters = .none
    /// For a wall of tiles playing at once, where sound from all of them is noise.
    var muted = false

    var body: some View {
        LoopingPlayerLayerView(url: url, look: look, muted: muted)
            .id(refreshToken)
    }
}

private struct LoopingPlayerLayerView: UIViewRepresentable {
    let url: URL
    var look: PersonalEffectParameters = .none
    var muted = false

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        /// What's on screen. The look is in here with the URL because changing
        /// either one means building a new player.
        struct Request: Equatable {
            let url: URL
            let look: PersonalEffectParameters
        }

        var looper: AVPlayerLooper?
        var loaded: Request?
        var building: Task<Void, Never>?

        deinit { building?.cancel() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        start(in: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        // SwiftUI reuses the UIView when only the URL changed (same view
        // identity) — rebuild the player or the old clip keeps looping.
        guard context.coordinator.loaded != Coordinator.Request(url: url, look: look) else { return }
        start(in: uiView, coordinator: context.coordinator)
    }

    private func start(in view: PlayerView, coordinator: Coordinator) {
        let request = Coordinator.Request(url: url, look: look)
        coordinator.loaded = request
        coordinator.building?.cancel()
        coordinator.building = nil

        // Off is the path this view has always taken: file straight to layer.
        guard !look.isIdentity else {
            play(request, composition: nil, in: view, coordinator: coordinator)
            return
        }

        // A look has to be ready *before* the first frame, because
        // `AVPlayerLooper` copies the template item for every pass — hand it an
        // unfiltered item now and every loop after this one is unfiltered too.
        // So the layer stays black for the moment it takes to read the tracks.
        coordinator.building = Task { @MainActor in
            let composition = await PersonalEffectFilter.playbackComposition(
                request.look, for: AVURLAsset(url: request.url))
            guard !Task.isCancelled, coordinator.loaded == request else { return }
            play(request, composition: composition, in: view, coordinator: coordinator)
        }
    }

    private func play(
        _ request: Coordinator.Request, composition: AVVideoComposition?,
        in view: PlayerView, coordinator: Coordinator
    ) {
        let item = AVPlayerItem(url: request.url)
        item.videoComposition = composition
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = muted
        coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        view.playerLayer.player = queuePlayer
        queuePlayer.play()
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        coordinator.building?.cancel()
        uiView.playerLayer.player?.pause()
    }
}

/// The shape of a video file, as it will be seen.
enum ClipGeometry {
    /// width / height after the file's own rotation, or nil if it can't be read.
    ///
    /// Worth measuring rather than assuming: a story knows which way its takes
    /// were filmed, but a stitched moment is a different shape from the takes
    /// inside it — two portrait takes side by side come out 9:8.
    static func aspect(of url: URL) async -> CGFloat? {
        guard let track = try? await AVURLAsset(url: url)
            .loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        let visible = CGRect(origin: .zero, size: size).applying(transform)
        guard abs(visible.height) > 0 else { return nil }
        return abs(visible.width) / abs(visible.height)
    }
}

/// First-frame stills, decoded once per file version. A library grid, a
/// story card and a room page all ask for the same frame; without this,
/// each view's `.task` reopens the video. The room page also redraws
/// every few seconds while it syncs — the same reason `AvatarImageCache`
/// exists — and "我的" destroys its grid when you flip to the calendar
/// and back, which would otherwise flash grey and decode everything again.
///
/// Keyed by the file, `recordedAt` (re-records reuse the name), the
/// requested time, and the pixel cap. Memory only; a memory warning
/// evicts entries through `NSCache`.
enum ClipThumbnailCache {
    static let defaultMaxSize = CGSize(width: 600, height: 600)
    /// The still `ClipThumbnail` asks for: a hair past the start, so a
    /// file whose first timestamp isn't exactly zero still has a frame.
    static let previewTime: Double = 0.1

    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // ~80 tiles at 600×600 would be more than we ever show at once;
        // the byte cap lets a handful of large frames coexist with a
        // long library without holding every one forever.
        cache.countLimit = 80
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func imageIfCached(
        url: URL,
        refreshToken: Date?,
        seconds: Double = previewTime,
        maxSize: CGSize = defaultMaxSize,
        exactTime: Bool = false
    ) -> UIImage? {
        images.object(forKey: key(
            url: url, refreshToken: refreshToken, seconds: seconds,
            maxSize: maxSize, exactTime: exactTime))
    }

    /// The cached still, or a newly decoded one. Off the caller's actor
    /// so a grid of misses doesn't stall the main thread.
    static func image(
        url: URL,
        refreshToken: Date?,
        seconds: Double = previewTime,
        maxSize: CGSize = defaultMaxSize,
        exactTime: Bool = false
    ) async -> UIImage? {
        if let cached = imageIfCached(
            url: url, refreshToken: refreshToken, seconds: seconds,
            maxSize: maxSize, exactTime: exactTime)
        {
            return cached
        }
        let generated = await generate(
            url: url, seconds: seconds, maxSize: maxSize, exactTime: exactTime)
        guard !Task.isCancelled else { return generated }
        if let generated {
            let cacheKey = key(
                url: url, refreshToken: refreshToken, seconds: seconds,
                maxSize: maxSize, exactTime: exactTime)
            // A twin request may have finished first; keep the stored
            // instance so callers can identity-compare a hit.
            if let existing = images.object(forKey: cacheKey) { return existing }
            images.setObject(generated, forKey: cacheKey, cost: cost(generated))
        }
        return generated
    }

    static func removeAll() {
        images.removeAllObjects()
    }

    private static func key(
        url: URL, refreshToken: Date?, seconds: Double,
        maxSize: CGSize, exactTime: Bool
    ) -> NSString {
        let token = refreshToken.map { String($0.timeIntervalSince1970) } ?? ""
        let time = String(format: "%.3f", seconds)
        let exact = exactTime ? "e" : "a"
        return "\(url.standardizedFileURL.path)|\(token)|\(time)|\(exact)|\(Int(maxSize.width))x\(Int(maxSize.height))" as NSString
    }

    private static func cost(_ image: UIImage) -> Int {
        let pixelCount = Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
        return max(pixelCount * 4, 1)
    }

    private static func generate(
        url: URL, seconds: Double, maxSize: CGSize, exactTime: Bool
    ) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = maxSize
            if exactTime {
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
            }
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let cgImage = try? await generator.image(at: time).image else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

/// First-frame thumbnail of a clip, loaded off the main thread.
struct ClipThumbnail: View {
    let url: URL
    /// Changing this value (e.g. recordedAt) forces a reload after re-recording.
    var refreshToken: Date?
    /// Fit the whole frame inside the tile, bedded on a blurred copy of itself,
    /// instead of cropping it to fill.
    ///
    /// A contact sheet wants every tile the same shape, and the clips are a
    /// different shape — a 9:16 take in a 0.72 tile. Closing that gap by
    /// cropping takes 22% off the height and scales the remainder up 28%, and
    /// what sits in the middle of a 1Day clip is a face. The bed keeps the
    /// tile's shape without ever cutting the picture.
    var bedsInsteadOfCrops = false

    @State private var image: UIImage?

    /// Prefer the cache in `body` so a tile that has been shown before
    /// doesn't flash the placeholder for a frame while `.task` starts.
    private var shown: UIImage? {
        image ?? ClipThumbnailCache.imageIfCached(url: url, refreshToken: refreshToken)
    }

    var body: some View {
        Group {
            if let shown {
                if bedsInsteadOfCrops {
                    // `Color.clear` takes the offered size and overlays don't
                    // feed back into it, so the filling bed can overflow
                    // without dragging the tile's own dimensions with it.
                    Color.clear
                        .overlay {
                            // `opaque: true`: a transparent-edged blur fades
                            // into nothing at the tile's border and leaves a
                            // pale halo inside the corner radius.
                            Image(uiImage: shown)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 14, opaque: true)
                                .overlay(Color.black.opacity(0.18))
                        }
                        .overlay {
                            Image(uiImage: shown)
                                .resizable()
                                .scaledToFit()
                        }
                        .clipped()
                } else {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                Color(.systemGray5)
            }
        }
        .task(id: taskID) {
            if let cached = ClipThumbnailCache.imageIfCached(url: url, refreshToken: refreshToken) {
                image = cached
                return
            }
            if let loaded = await ClipThumbnailCache.image(url: url, refreshToken: refreshToken) {
                image = loaded
            }
        }
    }

    /// `refreshToken` alone used to be the task id; the URL also belongs
    /// here, or a reused view identity pointing at a new file wouldn't reload.
    private var taskID: String {
        "\(url.standardizedFileURL.path)|\(refreshToken?.timeIntervalSince1970 ?? 0)"
    }
}
