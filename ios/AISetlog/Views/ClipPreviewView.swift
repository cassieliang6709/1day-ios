import SwiftUI
import AVFoundation

/// Looping playback of a single day's clip, with the option to re-record.
struct ClipPreviewView: View {
    let day: Int
    var slotTitle: String?
    var authorName: String?
    var overlayText: String?
    var clipLength: Challenge.ClipLength = .tiny
    let url: URL
    let recordedAt: Date?
    let onReRecord: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    LoopingClipPlayer(url: url)
                    MomentStampOverlay(
                        name: authorName,
                        momentTitle: slotTitle ?? "Day \(day)",
                        day: day,
                        mode: .review,
                        timestamp: recordedAt,
                        overlayText: overlayText,
                        clipSeconds: clipLength.seconds
                    )
                }
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Identity.tint(for: authorName), lineWidth: 3)
                }
                .frame(maxHeight: .infinity)

                if let recordedAt {
                    Text("Captured \(recordedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    onReRecord()
                } label: {
                    Label("Re-record this day", systemImage: "arrow.counterclockwise.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle(slotTitle ?? "Day \(day)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Endlessly looping muted-free playback of one clip. Fills its frame like
/// the live camera preview does (`.resizeAspectFill`) — SwiftUI's `VideoPlayer`
/// aspect-*fits* by default, which is what was letterboxing recorded clips
/// with black bars whenever the footage didn't exactly match the frame.
struct LoopingClipPlayer: View {
    let url: URL

    var body: some View {
        LoopingPlayerLayerView(url: url)
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
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        let queuePlayer = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = queuePlayer
        queuePlayer.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

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
