import SwiftUI
import AVFoundation

/// Endlessly looping muted-free playback of one clip. Fills its frame like
/// the live camera preview does (`.resizeAspectFill`) — SwiftUI's `VideoPlayer`
/// aspect-*fits* by default, which is what was letterboxing recorded clips
/// with black bars whenever the footage didn't exactly match the frame.
struct LoopingClipPlayer: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
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
        LoopingPlayerLayerView(
            url: url, look: look, muted: muted,
            isActive: isVisible && scenePhase == .active)
            .id(refreshToken)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }
}

private struct LoopingPlayerLayerView: UIViewRepresentable {
    let url: URL
    var look: PersonalEffectParameters = .none
    var muted = false
    var isActive = true

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
        var muted = false
        var isActive = true

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
        context.coordinator.muted = muted
        context.coordinator.isActive = isActive
        uiView.playerLayer.player?.isMuted = muted
        if isActive {
            uiView.playerLayer.player?.play()
        } else {
            uiView.playerLayer.player?.pause()
        }
        // SwiftUI reuses the UIView when only the URL changed (same view
        // identity) — rebuild the player or the old clip keeps looping.
        guard context.coordinator.loaded != Coordinator.Request(url: url, look: look) else { return }
        start(in: uiView, coordinator: context.coordinator)
    }

    private func start(in view: PlayerView, coordinator: Coordinator) {
        let request = Coordinator.Request(url: url, look: look)
        coordinator.muted = muted
        coordinator.isActive = isActive
        coordinator.loaded = request
        coordinator.building?.cancel()
        coordinator.building = nil
        view.playerLayer.player?.pause()
        coordinator.looper?.disableLooping()
        coordinator.looper = nil
        (view.playerLayer.player as? AVQueuePlayer)?.removeAllItems()
        view.playerLayer.player = nil

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
        queuePlayer.isMuted = coordinator.muted
        coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        view.playerLayer.player = queuePlayer
        if coordinator.isActive { queuePlayer.play() }
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        coordinator.building?.cancel()
        coordinator.building = nil
        coordinator.loaded = nil
        uiView.playerLayer.player?.pause()
        coordinator.looper?.disableLooping()
        coordinator.looper = nil
        (uiView.playerLayer.player as? AVQueuePlayer)?.removeAllItems()
        uiView.playerLayer.player = nil
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

    private var request: ClipThumbnailCache.Request {
        .init(url: url, refreshToken: refreshToken)
    }

    var body: some View {
        Group {
            if let image {
                if bedsInsteadOfCrops {
                    // `Color.clear` takes the offered size and overlays don't
                    // feed back into it, so the filling bed can overflow
                    // without dragging the tile's own dimensions with it.
                    Color.clear
                        .overlay {
                            // `opaque: true`: a transparent-edged blur fades
                            // into nothing at the tile's border and leaves a
                            // pale halo inside the corner radius.
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 14, opaque: true)
                                .overlay(Color.black.opacity(0.18))
                        }
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        }
                        .clipped()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                Color(.systemGray5)
            }
        }
        .task(id: request) {
            guard !Task.isCancelled else { return }
            let requested = request
            // A reused cell must not show its previous clip while decoding.
            image = ClipThumbnailCache.image(for: requested)
            guard image == nil else { return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            let frame = await withTaskCancellationHandler {
                try? await generator.image(at: time).image
            } onCancel: {
                generator.cancelAllCGImageGeneration()
            }
            guard !Task.isCancelled, requested == request, let frame else { return }
            let thumbnail = UIImage(cgImage: frame)
            ClipThumbnailCache.store(thumbnail, for: requested)
            image = thumbnail
        }
    }
}

/// Decoded frames are disposable: bound their memory and let NSCache evict
/// them under pressure. A re-record at the same URL is a different request.
@MainActor
enum ClipThumbnailCache {
    struct Request: Hashable {
        let url: URL
        let refreshToken: Date?

        var key: NSString {
            let path = url.absoluteString
            return "\(path.utf8.count):\(path):\(refreshToken.map { String($0.timeIntervalSince1970) } ?? "none")" as NSString
        }
    }

    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 120
        return cache
    }()

    static func image(for request: Request) -> UIImage? {
        images.object(forKey: request.key)
    }

    static func store(_ image: UIImage, for request: Request) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(image, forKey: request.key, cost: cost)
    }
}
