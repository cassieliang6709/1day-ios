import SwiftUI

/// The surfaces every screen is built on: the canvas behind everything, and
/// the floating glass card that sits on it. Controls live in
/// `OneDayControls.swift`; the palette in `Resources/Theme.swift`.

/// The page background — a pale blue canvas with a few out-of-focus blooms
/// drifting behind the content. They're what keeps a mostly-white app from
/// reading as a settings screen.
struct OneDayCanvas: View {
    /// Blooms shift with the screen so each surface feels like a different
    /// room in the same house.
    var seed: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The blooms hang in an overlay on a flexible colour rather than
        // sitting beside it in a ZStack. A ZStack adopts the width of its
        // largest child, so the 320pt bloom was setting the size of every
        // screen that used the canvas as a sibling of its content — pushing
        // the layout ~60pt wider than the display and cropping both edges.
        // An overlay is sized by its base, so decoration can't do that.
        OneDay.canvas
            .overlay {
                // In dark mode the pale blooms read as a hard white flare over
                // the top of the screen — the headline sits in it and stops
                // being legible. Dark keeps the same shapes as a dim brand
                // glow instead: decoration, never a spotlight.
                ZStack {
                    bloom(.oneDayMist, dark: .oneDayBrand,
                          size: 320, x: -140, y: -280, opacity: 0.9, darkOpacity: 0.16)
                    bloom(.oneDaySky, dark: .oneDayCyan,
                          size: 260, x: 170, y: -180, opacity: 0.28, darkOpacity: 0.10)
                    bloom(.oneDayLavender, dark: .oneDayLavender,
                          size: 300, x: 160, y: 380, opacity: 0.16, darkOpacity: 0.10)
                    bloom(.oneDayMint, dark: .oneDayMint,
                          size: 200, x: -160, y: 460, opacity: 0.14, darkOpacity: 0.09)
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }

    private func bloom(
        _ color: Color,
        dark darkColor: Color,
        size: CGFloat,
        x: CGFloat,
        y: CGFloat,
        opacity: Double,
        darkOpacity: Double
    ) -> some View {
        let isDark = colorScheme == .dark
        return Circle()
            .fill((isDark ? darkColor : color).opacity(isDark ? darkOpacity : opacity))
            .frame(width: size, height: size)
            .blur(radius: 48)
            .offset(x: x + CGFloat(seed % 3) * 18, y: y - CGFloat(seed % 2) * 24)
    }
}

/// A floating glass card: translucent white, hairline edge, soft ambient lift.
/// The app's default container — use it instead of stacking bordered boxes.
///
/// Padding plus `glassSurface` and nothing else. The two used to carry their
/// own copies of the same fill/tint/stroke/shadow stack, which is how a fix to
/// one (the dark-mode shadow) would have quietly missed the other.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = OneDay.Radius.card
    var padding: CGFloat = 18
    /// A tinted card for the one thing on screen that matters most.
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(radius: radius, tint: tint)
    }
}

extension View {
    /// Glass treatment for a view that builds its own padding. The single
    /// implementation behind `GlassCard` too.
    func glassSurface(
        radius: CGFloat = OneDay.Radius.card,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape
                .fill(OneDay.surface)
                .overlay {
                    if let tint {
                        shape.fill(tint.opacity(0.10))
                    }
                }
        }
        .overlay {
            shape.strokeBorder(OneDay.hairline, lineWidth: 1)
        }
        .oneDaySoftShadow()
    }
}

// MARK: - Controls over footage

/// Dark glass for anything that floats on a live camera feed or a playing
/// clip: white glyphs on a black-tinted material, in both appearances.
///
/// Why not `.regularMaterial` / `.ultraThinMaterial` on their own: a system
/// material follows the *device's* appearance. In light mode it turns
/// near-white, so a white label on it over a bright frame is white on white;
/// in dark mode the app's themed inks (`oneDayNavy` → #9AB7FF) land pale on
/// pale. Footage has no appearance — it is whatever the camera saw — so the
/// control has to bring its own contrast. This pins the material dark,
/// darkens it further with a black wash (so it still reads over a sunlit
/// sky), and adds a hairline so the edge holds against a black frame too.
///
/// It sets the foreground to white, so pass content with no colour of its own.
/// The same recipe `CameraComponents`' zoom capsule already used by hand.
struct OverVideoGlass<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .background(.black.opacity(0.28), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
            // Last, so it reaches the material and anything inside the label
            // (a `.secondary` style, a `ProgressView`) that resolves by scheme.
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Dark-glass backing for a control over video. See `OverVideoGlass`.
    ///
    ///     Label(…).padding(…).overVideoControl()            // capsule
    ///     Image(systemName: "xmark").frame(…).overVideoControl(in: Circle())
    func overVideoControl<S: InsettableShape>(in shape: S) -> some View {
        modifier(OverVideoGlass(shape: shape))
    }

    /// Capsule, the app's default control shape.
    func overVideoControl() -> some View {
        modifier(OverVideoGlass(shape: Capsule()))
    }
}

// MARK: - Brand artwork and small illustrations

/// The current 1day lockup: the blue mascot leads, with the handwritten name
/// kept secondary. Its transparent artwork can sit directly on app surfaces.
struct OneDayBrandLogo: View {
    var width: CGFloat = 96

    var body: some View {
        Image(AppSkin.lockupImageName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width * 0.49)
            .accessibilityLabel("1Day")
    }
}

/// The mascot: the drawn artwork, in the same ringed circle it wears as an
/// avatar. Shows up wherever the app is doing something on the user's behalf
/// (stitching, waiting on a friend) or has nothing to show yet.
///
/// It used to draw its own face — a rounded rectangle, two white dots and a
/// stroked arc. That reads as a placeholder for a mascot rather than as one,
/// and at the sizes this is used at (68–78pt on an otherwise empty screen) it
/// is the only thing on the page. `AvatarDot` with no name already renders the
/// real artwork, and it is the face the user knows from the top left of the
/// home screen, so the two places the app shows itself now agree.
struct OneDayBuddy: View {
    var size: CGFloat = 44
    /// Breathes gently while something is in progress.
    var isWorking = false

    @State private var breathe = false
    /// A loop that never ends is exactly what Reduce Motion asks apps to
    /// stop. The mascot holds still instead; the screen it sits on already
    /// says in words that something is happening.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AvatarDot(name: nil, size: size)
            .scaleEffect(breathe ? 0.94 : 1)
            .animation(OneDay.Motion.reduced(OneDay.Motion.pulse, if: reduceMotion), value: breathe)
            .onAppear { breathe = isWorking && !reduceMotion }
            // Turned on mid-loop: settle back to rest, without animating there.
            .onChange(of: reduceMotion) { _, reduced in
                breathe = isWorking && !reduced
            }
    }
}

extension View {
    /// Lays the view out inside a box of fixed height spanning the available
    /// width, clipping whatever spills.
    ///
    /// Use this for any clip thumbnail. `ClipThumbnail` aspect-*fills*, so its
    /// ideal width is `height × aspect` — put one straight into
    /// `.frame(height:)` and a landscape clip demands ~459pt at 258pt tall,
    /// which widens the enclosing stack and pushes the whole screen past the
    /// display. Content in an overlay cannot resize its base, so the box wins.
    func clipBox(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay { self }
            .clipped()
    }
}

/// A dotted "nothing here yet" frame — the empty state for a moment that
/// hasn't been filmed. Reads as an unexposed film cell, not a missing task.
struct EmptyFrame<Content: View>: View {
    var radius: CGFloat = OneDay.Radius.chip
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(OneDay.surfaceSoft.opacity(0.45), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        Color.oneDaySky.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
    }
}
