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
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OneDay.surface)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(tint.opacity(0.10))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(OneDay.hairline, lineWidth: 1)
            }
            .oneDaySoftShadow()
    }
}

extension View {
    /// Glass treatment for a view that builds its own padding.
    func glassSurface(
        radius: CGFloat = OneDay.Radius.card,
        tint: Color? = nil
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(OneDay.surface)
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(tint.opacity(0.10))
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(OneDay.hairline, lineWidth: 1)
        }
        .oneDaySoftShadow()
    }
}

// MARK: - Brand artwork and small illustrations

/// The current 1day lockup: the blue mascot leads, with the handwritten name
/// kept secondary. Its transparent artwork can sit directly on app surfaces.
struct OneDayBrandLogo: View {
    var width: CGFloat = 96

    var body: some View {
        Image("OneDayBrandLockup")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width * 0.49)
            .accessibilityLabel("1Day")
    }
}

/// The app mark: a rounded blue tile with a lens and a shutter dot.
struct OneDayLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .fill(OneDay.brand)
                    .oneDayGlow(strength: side / 92)

                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: max(side * 0.055, 2))
                    .frame(width: side * 0.46, height: side * 0.46)

                Circle()
                    .fill(.white)
                    .frame(width: side * 0.11, height: side * 0.11)
                    .offset(x: side * 0.23, y: -side * 0.23)
            }
        }
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

    var body: some View {
        AvatarDot(name: nil, size: size)
            .scaleEffect(breathe ? 0.94 : 1)
            .animation(
                .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: breathe)
            .onAppear {
                guard isWorking else { return }
                breathe = true
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
