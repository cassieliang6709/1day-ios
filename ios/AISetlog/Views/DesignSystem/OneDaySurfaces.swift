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

    var body: some View {
        ZStack {
            OneDay.canvas.ignoresSafeArea()

            bloom(.oneDayMist, size: 320, x: -140, y: -280, opacity: 0.9)
            bloom(.oneDaySky, size: 260, x: 170, y: -180, opacity: 0.28)
            bloom(.oneDayLavender, size: 300, x: 160, y: 380, opacity: 0.16)
            bloom(.oneDayMint, size: 200, x: -160, y: 460, opacity: 0.14)
        }
        .ignoresSafeArea()
    }

    private func bloom(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(color.opacity(opacity))
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
                    .fill(.background)
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
                .fill(.background)
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

// MARK: - Small illustrations
//
// A couple of hand-drawn-feeling marks. They carry the "cute" without any
// image assets — pure shapes, so they tint and scale with the layout.

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

/// The mascot: a soft blue blob with two dot eyes. Shows up wherever the app
/// is doing something on the user's behalf (stitching, waiting on a friend).
struct OneDayBuddy: View {
    var size: CGFloat = 44
    /// Eyes close and the body squashes gently while something is in progress.
    var isWorking = false

    @State private var breathe = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                .fill(OneDay.brand)
                .frame(width: size, height: size * (breathe ? 0.94 : 1))

            HStack(spacing: size * 0.18) {
                eye
                eye
            }
            .offset(y: -size * 0.04)

            // A little smile.
            Capsule()
                .fill(.white.opacity(0.85))
                .frame(width: size * 0.22, height: size * 0.06)
                .offset(y: size * 0.2)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard isWorking else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var eye: some View {
        Circle()
            .fill(.white)
            .frame(width: size * 0.13, height: size * 0.13)
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
