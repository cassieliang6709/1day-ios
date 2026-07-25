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

    var body: some View {
        LoopingPlayerLayerView(url: url)
            .id(refreshToken)
    }
}

private struct LoopingPlayerLayerView: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        context.coordinator.loadedURL = url
        let queuePlayer = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = queuePlayer
        queuePlayer.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        // SwiftUI reuses the UIView when only the URL changed (same view
        // identity) — rebuild the player or the old clip keeps looping.
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        let queuePlayer = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
        uiView.playerLayer.player = queuePlayer
        queuePlayer.play()
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
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
