import SwiftUI
import AVFoundation

struct LoopingClipPlayer: View {
    let url: URL
    var refreshToken: Date? = nil
    var look: PersonalEffectParameters = .none
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
        guard context.coordinator.loaded != Coordinator.Request(url: url, look: look) else { return }
        start(in: uiView, coordinator: context.coordinator)
    }

    private func start(in view: PlayerView, coordinator: Coordinator) {
        let request = Coordinator.Request(url: url, look: look)
        coordinator.loaded = request
        coordinator.building?.cancel()
        coordinator.building = nil

        guard !look.isIdentity else {
            play(request, composition: nil, in: view, coordinator: coordinator)
            return
        }

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
