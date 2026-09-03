import AVFoundation
import SwiftUI

/// The first screen is deliberately a promise, not a tutorial: three tiny
/// moments become one film. More capable creation stays available after the
/// first film, once there is something meaningful to build on.
struct FirstRunOnboardingView: View {
    let onCreateStory: () -> Void
    let onJoin: () -> Void

    /// Bound so Settings changes immediately redraw the localized lockup and
    /// copy even before someone has made their first story.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 1)

            GeometryReader { proxy in
                let isCompactHeight = proxy.size.height < 700
                let horizontalInset = min(max(proxy.size.width * 0.08, 24), 36)
                let sampleWidth = min(
                    min(
                        proxy.size.width * (isCompactHeight ? 0.48 : 0.60),
                        proxy.size.height * (isCompactHeight ? 0.28 : 0.25)),
                    280)

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: max(proxy.size.height * 0.04, 18))

                        brand

                        Text(Strings.firstRunHeadline)
                            .font(.system(size: 31, weight: .heavy, design: .rounded))
                            .foregroundStyle(OneDay.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.76)
                            .padding(.top, isCompactHeight ? 20 : 26)

                        equation
                            .padding(.top, isCompactHeight ? 17 : 24)

                        Text(Strings.firstRunGuide)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .padding(.top, 10)

                        SampleFilmCard()
                            .frame(width: sampleWidth)
                            .padding(.top, isCompactHeight ? 18 : 28)

                        Button(action: onCreateStory) {
                            Text(Strings.firstRunStart)
                        }
                        .buttonStyle(.primaryAction)
                        .accessibilityHint(Strings.firstRunStartHint)
                        .padding(.top, isCompactHeight ? 26 : 38)

                        Button(action: onJoin) {
                            Text(Strings.firstRunJoin)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(OneDay.inkSoft)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, isCompactHeight ? 20 : 27)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, horizontalInset)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            OneDayBuddy(size: 54)
            Text("1Day")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("1Day")
    }

    private var equation: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("3")
                .font(.system(size: 31, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.oneDayBlue)
            Text(Strings.firstRunThreeMoments)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
            Image(systemName: "arrow.right")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(OneDay.inkFaint)
                .padding(.horizontal, 2)
            Text("1")
                .font(.system(size: 31, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.oneDayBlue)
            Text(Strings.firstRunOneFilm)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.66)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Strings.firstRunEquationAccessibility)
    }
}

/// A real, looping sample film so the first screen shows the product's payoff
/// before anyone has to make their own story.
private struct SampleFilmCard: View {
    @State private var isPlaying = true

    private var sampleURL: URL? {
        Bundle.main.url(forResource: "sample-film", withExtension: "mp4")
    }

    var body: some View {
        Group {
            if let sampleURL {
                Button {
                    isPlaying.toggle()
                } label: {
                    videoPreview(url: sampleURL)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.firstRunSampleFilmAccessibility)
                .accessibilityHint(
                    isPlaying
                        ? Strings.firstRunSampleFilmPause
                        : Strings.firstRunSampleFilmPlay)
            } else {
                SampleFilmFallback()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Strings.firstRunSampleFilmAccessibility)
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .onAppear { isPlaying = true }
        .accessibilityIdentifier("onboardingSampleFilm")
    }

    @ViewBuilder
    private func videoPreview(url: URL) -> some View {
        ZStack(alignment: .bottomLeading) {
            MutedLoopingSamplePlayer(url: url, isPlaying: isPlaying)

            LinearGradient(
                colors: [.clear, .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 92)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.quickStartTitle)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text("0:12")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(14)

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.28), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.64), lineWidth: 1.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.78), lineWidth: 5)
        }
        .oneDaySoftShadow(strength: 1.1)
    }
}

/// A static preview keeps the onboarding understandable if the bundle is
/// accidentally stripped by a build configuration.
private struct SampleFilmFallback: View {
    private let frames = [
        "TemplatePerfectDay",
        "TemplateMainCharacter",
        "TemplateLittleAdventure",
    ]

    var body: some View {
        GeometryReader { proxy in
            let stripHeight = proxy.size.height / 3

            ZStack(alignment: .bottomLeading) {
                VStack(spacing: 2) {
                    ForEach(frames, id: \.self) { name in
                        Image(name)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: stripHeight - 1)
                            .clipped()
                            .overlay(alignment: .bottomLeading) {
                                Text("0:02")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.38), radius: 3, y: 1)
                                    .padding(10)
                            }
                    }
                }

                Image(systemName: "play.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(.black.opacity(0.28), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.64), lineWidth: 1.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 92)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.quickStartTitle)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                    Text("0:06")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.78), lineWidth: 5)
            }
            .oneDaySoftShadow(strength: 1.1)
        }
    }
}

private struct MutedLoopingSamplePlayer: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = context.coordinator.player
        configure(context.coordinator)
        context.coordinator.player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if context.coordinator.loadedURL != url {
            configure(context.coordinator)
        }
        isPlaying ? context.coordinator.player.play() : context.coordinator.player.pause()
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
    }

    private func configure(_ coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.player.removeAllItems()
        coordinator.player.isMuted = true
        coordinator.loadedURL = url
        coordinator.looper = AVPlayerLooper(
            player: coordinator.player,
            templateItem: AVPlayerItem(url: url))
    }
}
