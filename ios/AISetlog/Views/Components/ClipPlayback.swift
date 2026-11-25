import SwiftUI
import AVFoundation

struct LoopingClipPlayer: View {
    let url: URL
    var refreshToken: Date? = nil
    var muted = false
    var fits = false

    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        LoopingPlayerLayerView(
            url: url, muted: muted, fits: fits, isActive: isVisible && scenePhase == .active)
            .id(refreshToken)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }
}

private struct LoopingPlayerLayerView: UIViewRepresentable {
    let url: URL
    var muted = false
    var fits = false
    var isActive = true

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
        var loaded: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = fits ? .resizeAspect : .resizeAspectFill
        start(in: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if context.coordinator.loaded != url {
            start(in: uiView, coordinator: context.coordinator)
        }
        uiView.playerLayer.player?.isMuted = muted
        if isActive {
            uiView.playerLayer.player?.play()
        } else {
            uiView.playerLayer.player?.pause()
        }
    }

    private func start(in view: PlayerView, coordinator: Coordinator) {
        coordinator.loaded = url
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = muted
        coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        view.playerLayer.player = queuePlayer
        if isActive { queuePlayer.play() }
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
    }
}

enum ClipGeometry {
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

struct ClipThumbnail: View {
    let url: URL
    var refreshToken: Date?
    var bedsInsteadOfCrops = false

    @State private var image: UIImage?

    private struct Request: Equatable {
        let url: URL
        let refreshToken: Date?
    }

    var body: some View {
        Group {
            if let image {
                if bedsInsteadOfCrops {
                    Color.clear
                        .overlay {
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
        .task(id: Request(url: url, refreshToken: refreshToken)) {
            image = nil
            let loaded = await ClipThumbnailCache.shared.image(for: url, refreshToken: refreshToken)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
