import AuthenticationServices
import SwiftUI

/// The first screen is deliberately a promise, not a tutorial: a few moments
/// become one film. More capable creation stays available after the
/// first film, once there is something meaningful to build on.
struct FirstRunOnboardingView: View {
    let onCreateStory: () -> Void

    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var signInError: String?
    /// The avatar's three steps, between signing in and the camera.
    @State private var showsAvatarSetup = false

    /// Bound so Settings changes immediately redraw the localized lockup and
    /// copy even before someone has made their first story.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 1)

            GeometryReader { proxy in
                let isCompactHeight = proxy.size.height < 700
                let horizontalInset = min(max(proxy.size.width * 0.08, 24), 36)
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

                        SameDayAnimation()
                            .frame(height: isCompactHeight ? 200 : 250)
                            .padding(.top, isCompactHeight ? 10 : 18)

                        Text(Strings.firstRunGuide)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)

                        // One way on from here: 通过 Apple 继续. Joining by
                        // code and filming solo both wait until after sign-in.
                        primaryAction
                            .padding(.top, isCompactHeight ? 26 : 38)

                        Spacer().frame(height: 18)
                    }
                    .padding(.horizontal, horizontalInset)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        // A reinstall gets its Apple ID offered before anything is tapped.
        .task { account.offerExistingAccount() }
        // Made or skipped, the camera is next.
        .fullScreenCover(isPresented: $showsAvatarSetup, onDismiss: onCreateStory) {
            AvatarSetupFlow { _ in showsAvatarSetup = false }
        }
    }

    /// Signing in comes first, because filming together is what most people
    /// come for, and asking halfway through a join — a sheet over a sheet — is
    /// where it kept going wrong. It is the only button on the page.
    @ViewBuilder
    private var primaryAction: some View {
        if account.isSignedIn {
            Button(action: onCreateStory) {
                Text(Strings.firstRunStart)
            }
            .buttonStyle(.primaryAction)
            .accessibilityHint(Strings.firstRunStartHint)
        } else {
            VStack(spacing: 8) {
                SignInWithAppleButton(.continue) { request in
                    account.configure(request)
                } onCompletion: { result in
                    do {
                        try account.completeSignIn(result)
                        // An avatar already on this phone skips the three steps.
                        if AvatarStore.shared.image == nil {
                            showsAvatarSetup = true
                        } else {
                            onCreateStory()
                        }
                    } catch {
                        if (error as? ASAuthorizationError)?.code == .canceled { return }
                        signInError = Strings.signInFailed
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(Capsule())

                Text(signInError ?? Strings.firstRunSignInNote)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(signInError == nil ? OneDay.inkSoft : Color.oneDayEmber)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The brand artwork, not an imitation of it.
    ///
    /// This was `OneDayBuddy` beside `Text("1Day")` in the system rounded face,
    /// with a hand-picked gap — a lockup assembled in code, and the only place
    /// in the product where the name appears at all. It drew a different
    /// character from the one on the app icon the person had just tapped: a
    /// gradient tile with no arms against a flat blue blob with two of them.
    /// Every proportion in it was also somebody's guess, and the next guess
    /// would have been a different one.
    ///
    /// `OneDayBrandLogo` has been in the app since the artwork was added and
    /// had no callers. The relationship between the mark and the word lives in
    /// the asset now, where nothing here can drift it.
    private var brand: some View {
        OneDayBrandLogo(width: 196)
    }
}

/// The headline, shown: three people each film their own take of the same
/// moment, and the takes slide together into one split frame that plays —
/// which is exactly what a shared room's film looks like at that moment.
///
/// It replaced a strip of film with a play button. That one said "clips become
/// a film", which the line under it already says; this says the part only
/// 1Day does, that the film is everyone's at once.
///
/// Drawn, not filmed: nothing to bundle, and it follows light and dark.
private struct SameDayAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Int, CaseIterable {
        case empty, first, second, third, together, playing
    }

    private struct Take {
        let name: String
        /// nil draws a person glyph: the viewer has no name yet on this screen,
        /// and 「你」 in the dot beside 「你」 read twice.
        let initial: String?
        let tint: Color
        let colors: [Color]
        let apart: CGPoint
        let tilt: Double
        let together: CGPoint
    }

    /// Laid out on this canvas and scaled to the room the screen gives it, so
    /// the choreography never has to be re-measured.
    private static let canvas = CGSize(width: 260, height: 250)
    private static let take = CGSize(width: 68, height: 124)
    /// The three takes side by side, edge to edge, like the film's split frame.
    private static let frame = CGRect(x: 28, y: 52, width: 204, height: 124)

    /// Stepped by a loop rather than `PhaseAnimator`: the drawn people inside
    /// each take redraw every frame, and under `PhaseAnimator` that kept the
    /// sequence from ever leaving its first step.
    @State private var phase: Phase = .empty

    private var takes: [Take] {
        [
            Take(name: Strings.firstRunTakeYou, initial: nil,
                 tint: Color(uiColor: .identityAmber),
                 colors: [Color(red: 0.62, green: 0.82, blue: 1), Color(red: 0.8, green: 0.88, blue: 1)],
                 apart: CGPoint(x: 46, y: 118), tilt: -8,
                 together: CGPoint(x: 62, y: 114)),
            Take(name: "Mia", initial: "M",
                 tint: Color.oneDayBrand,
                 colors: [.oneDayButter, .oneDayBlush],
                 apart: CGPoint(x: 130, y: 100), tilt: 2,
                 together: CGPoint(x: 130, y: 114)),
            Take(name: "Sam", initial: "S",
                 tint: Color(uiColor: .identityTeal),
                 colors: [Color(red: 0.78, green: 0.94, blue: 0.86), Color(red: 0.62, green: 0.86, blue: 0.95)],
                 apart: CGPoint(x: 214, y: 122), tilt: 8,
                 together: CGPoint(x: 198, y: 114)),
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.canvas.width,
                            proxy.size.height / Self.canvas.height)
            Group {
                if reduceMotion {
                    // The end state, still: the point survives without the motion.
                    drawing(at: .playing)
                } else {
                    drawing(at: phase)
                        .task { await run() }
                }
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height)
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.firstRunAnimationAccessibility)
    }

    /// Each step: wait, then animate into it. The progress bar's run is the
    /// `.playing` step's length.
    private func run() async {
        let steps: [(Phase, Animation, Double)] = [
            (.first, .spring(duration: 0.5, bounce: 0.3), 0.5),
            (.second, .spring(duration: 0.5, bounce: 0.3), 0.45),
            (.third, .spring(duration: 0.5, bounce: 0.3), 0.45),
            (.together, .smooth(duration: 0.6), 0.9),
            (.playing, .linear(duration: 2.2), 0.6),
            (.empty, .easeIn(duration: 0.25), 3.0),
        ]
        while !Task.isCancelled {
            for (next, animation, wait) in steps {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                withAnimation(animation) { phase = next }
            }
        }
    }

    private func drawing(at phase: Phase) -> some View {
        let joined = phase.rawValue >= Phase.together.rawValue
        return ZStack(alignment: .topLeading) {
            // The split frame's border, drawn behind so the takes fill it.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(OneDay.surface)
                .frame(width: Self.frame.width + 10, height: Self.frame.height + 10)
                .position(x: Self.frame.midX, y: Self.frame.midY)
                .oneDaySoftShadow(strength: 1)
                .opacity(joined ? 1 : 0)
                .scaleEffect(joined ? 1 : 0.92)

            ForEach(Array(takes.enumerated()), id: \.offset) { index, take in
                let shown = phase.rawValue >= index + 1
                takeCard(take, index: index, joined: joined)
                    .rotationEffect(.degrees(joined ? 0 : take.tilt))
                    .position(joined ? take.together : take.apart)
                    .offset(y: shown ? 0 : -24)
                    .opacity(shown ? 1 : 0)
            }

            playbackBar(progress: phase == .playing ? 1 : 0)
                .position(x: Self.frame.midX, y: Self.frame.maxY + 26)
                .opacity(joined ? 1 : 0)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
    }

    /// Apart, each take is its own rounded card with its owner on it; joined,
    /// only the outer corners stay round, so the three read as one picture.
    private func takeCard(_ take: Take, index: Int, joined: Bool) -> some View {
        let r: CGFloat = 16
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: !joined || index == 0 ? r : 0,
            bottomLeadingRadius: !joined || index == 0 ? r : 0,
            bottomTrailingRadius: !joined || index == 2 ? r : 0,
            topTrailingRadius: !joined || index == 2 ? r : 0,
            style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: take.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            // A person in each take, so the three read as three people's
            // moments rather than three coloured blocks.
            TakeScene(kind: TakeScene.Kind(rawValue: index) ?? .wave)
            HStack(spacing: 5) {
                Group {
                    if let initial = take.initial {
                        Text(initial).font(.system(size: 10, weight: .heavy, design: .rounded))
                    } else {
                        Image(systemName: "person.fill").font(.system(size: 9, weight: .bold))
                    }
                }
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(take.tint, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                Text(take.name)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(7)
        }
        .frame(width: Self.take.width, height: Self.take.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(joined ? 0 : 0.14), radius: 8, y: 4)
    }

    /// Under the joined frame: the film playing, not a button promising it will.
    private func playbackBar(progress: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(OneDay.brandText)
            Capsule()
                .fill(OneDay.surfaceSoft)
                .frame(width: 150, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.oneDayBrand)
                        .frame(width: 150 * progress, height: 5)
                }
        }
    }
}

/// One take's picture on the first-run animation: a 1day mascot in a small
/// place, moving. Yellow waves under a sun, blue sways beside a steaming cup,
/// mint bounces in a park. Still under Reduce Motion.
private struct TakeScene: View {
    enum Kind: Int { case wave, coffee, park }
    let kind: Kind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                ZStack {
                    props(t: t, w: w, h: h)
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58)
                        .rotationEffect(.degrees(tilt(t)), anchor: .bottom)
                        .scaleEffect(squash(t), anchor: .bottom)
                        .position(x: w * 0.5, y: h - 40 + bounce(t))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var imageName: String {
        switch kind {
        case .wave: "OneDayBuddyYellow"
        case .coffee: "OneDayBuddyBlue"
        case .park: "OneDayBuddyMint"
        }
    }

    private func tilt(_ t: Double) -> Double {
        switch kind {
        case .wave: 9 * sin(t * 4)
        case .coffee: 4 * sin(t * 1.6)
        case .park: 0
        }
    }

    private func bounce(_ t: Double) -> CGFloat {
        kind == .park ? CGFloat(-abs(sin(t * 3.2)) * 9) : CGFloat(sin(t * 2) * 1.2)
    }

    /// A little squash at the bottom of each hop, so the bounce lands.
    private func squash(_ t: Double) -> CGFloat {
        guard kind == .park else { return 1 }
        let ground = 1 - abs(sin(t * 3.2))
        return 1 - CGFloat(max(0, ground - 0.8)) * 0.4
    }

    @ViewBuilder
    private func props(t: Double, w: CGFloat, h: CGFloat) -> some View {
        switch kind {
        case .wave:
            Circle()
                .fill(Color(red: 1, green: 0.85, blue: 0.35))
                .frame(width: 22, height: 22)
                .shadow(color: .yellow.opacity(0.6), radius: 6)
                .position(x: w * 0.72, y: 26 + CGFloat(sin(t)) * 2)
            Capsule()
                .fill(.white.opacity(0.8))
                .frame(width: 26, height: 9)
                .position(x: w * 0.3 + CGFloat(sin(t / 2)) * 4, y: 40)
        case .coffee:
            // A cup on the right, steam rising off it.
            RoundedRectangle(cornerRadius: 3)
                .fill(.white)
                .frame(width: 13, height: 14)
                .overlay(alignment: .trailing) {
                    Circle().strokeBorder(.white, lineWidth: 2.5)
                        .frame(width: 8, height: 8).offset(x: 5)
                }
                .position(x: w * 0.82, y: h - 30)
            ForEach(0..<2, id: \.self) { i in
                let phase = (t * 0.8 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                Capsule()
                    .fill(.white.opacity(0.85 * (1 - phase)))
                    .frame(width: 2.5, height: 7)
                    .position(x: w * 0.82 - 2 + CGFloat(i) * 4, y: h - 42 - CGFloat(phase) * 14)
            }
        case .park:
            Ellipse()
                .fill(Color(red: 0.42, green: 0.74, blue: 0.48))
                .frame(width: w * 1.6, height: 40)
                .position(x: w * 0.5, y: h + 8)
            Circle()
                .fill(Color(red: 0.3, green: 0.62, blue: 0.4))
                .frame(width: 22, height: 22)
                .position(x: w * 0.8, y: 34)
            Rectangle()
                .fill(Color(red: 0.45, green: 0.3, blue: 0.2))
                .frame(width: 3, height: 14)
                .position(x: w * 0.8, y: 51)
        }
    }
}
