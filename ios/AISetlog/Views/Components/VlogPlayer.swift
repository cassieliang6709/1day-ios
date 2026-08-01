import SwiftUI
import AVKit
import Observation

/// The finished film, with chrome that matches the rest of the app.
///
/// `VideoPlayer` brings UIKit's control bar, which drops a grey system slab
/// into an otherwise soft blue screen. This wraps `AVPlayer` directly so the
/// transport is ours: a capsule scrubber, rounded corners, and no chrome at
/// all until you reach for it.

@Observable
final class VlogPlayback {
    let player: AVPlayer
    var isPlaying = false
    var current: Double = 0
    var duration: Double = 0
    /// True while the user drags, so the observer doesn't fight the thumb.
    var isScrubbing = false

    private var timeObserver: Any?

    init(url: URL) {
        player = AVPlayer(url: url)
        observe()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    private func observe() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, !isScrubbing else { return }
            current = time.seconds
            if let itemDuration = player.currentItem?.duration.seconds,
               itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            isPlaying = false
            current = duration
        }
    }

    func toggle() {
        if isPlaying {
            player.pause()
        } else {
            // Replaying from the end should start over, not sit on the last frame.
            if duration > 0, current >= duration - 0.05 { seek(to: 0) }
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        current = seconds
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(current / duration, 0), 1)
    }

    static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct VlogPlayer: View {
    let url: URL
    var aspectRatio: CGFloat = 9 / 16
    /// Autoplay once the film first appears — the payoff shouldn't need a tap.
    var autoplay = true

    @State private var playback: VlogPlayback
    @State private var showsChrome = true
    @State private var expanded = false

    init(url: URL, aspectRatio: CGFloat = 9 / 16, autoplay: Bool = true) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.autoplay = autoplay
        _playback = State(initialValue: VlogPlayback(url: url))
    }

    var body: some View {
        // Chrome hangs off the player as overlays rather than sitting beside it
        // in a ZStack: the video is aspect-fit, so it's narrower than the space
        // it's given, and a sibling control bar would overhang its corners.
        PlayerSurface(player: playback.player)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous))
            .onTapGesture {
                withAnimation(OneDay.Motion.snap) { showsChrome.toggle() }
            }
            .overlay(alignment: .bottom) {
                if showsChrome {
                    controls
                        .padding(10)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .overlay {
                if !playback.isPlaying { bigPlayButton }
            }
            .overlay {
                RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
        .oneDaySoftShadow(strength: 1.2)
        .onAppear {
            guard autoplay else { return }
            playback.toggle()
        }
        .onDisappear { playback.pause() }
        .fullScreenCover(isPresented: $expanded) {
            FullscreenFilm(url: url) { expanded = false }
        }
    }

    private var bigPlayButton: some View {
        Button { playback.toggle() } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.oneDayBlue)
                .frame(width: 62, height: 62)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .oneDaySoftShadow()
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { playback.toggle() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.2), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Scrubber(playback: playback)

            Text("\(VlogPlayback.timecode(playback.current)) / \(VlogPlayback.timecode(playback.duration))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))

            Button { expanded = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}

/// A capsule progress track you can drag. Grows under the finger so the thumb
/// never hides the position it's setting.
private struct Scrubber: View {
    @Bindable var playback: VlogPlayback
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule()
                    .fill(.white)
                    .frame(width: max(width * playback.progress, 3))
            }
            .frame(height: isDragging ? 7 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        guard playback.duration > 0 else { return }
                        playback.isScrubbing = true
                        let ratio = min(max(value.location.x / width, 0), 1)
                        playback.current = ratio * playback.duration
                    }
                    .onEnded { _ in
                        playback.seek(to: playback.current)
                        playback.isScrubbing = false
                    }
            )
            .animation(OneDay.Motion.snap, value: isDragging)
        }
        .frame(height: 22)
    }
}

/// AVPlayerLayer without UIKit's transport controls.
private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: LayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

/// Fullscreen playback falls back to the system player — at that point the
/// user wants scrubbing, AirPlay and PiP more than they want our styling.
private struct FullscreenFilm: View {
    let url: URL
    let onClose: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
            IconBubble(systemName: "xmark", tint: .white, action: onClose)
                .padding(18)
        }
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
