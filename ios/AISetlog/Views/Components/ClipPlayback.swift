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
    var look: GentleLook = .none

    var body: some View {
        LoopingPlayerLayerView(url: url, look: look)
            .id(refreshToken)
    }
}

private struct LoopingPlayerLayerView: UIViewRepresentable {
    let url: URL
    var look: GentleLook = .none

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        /// What's on screen. The look is in here with the URL because changing
        /// either one means building a new player.
        struct Request: Equatable {
            let url: URL
            let look: GentleLook
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
            let composition = await GentleLookFilter.playbackComposition(
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
        coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        view.playerLayer.player = queuePlayer
        queuePlayer.play()
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        coordinator.building?.cancel()
        uiView.playerLayer.player?.pause()
    }
}

/// First-frame thumbnail of a clip, loaded off the main thread.
struct ClipThumbnail: View {
    let url: URL
    /// Changing this value (e.g. recordedAt) forces a reload after re-recording.
    var refreshToken: Date?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray5)
            }
        }
        .task(id: refreshToken) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                image = UIImage(cgImage: cgImage)
            }
        }
    }
}
