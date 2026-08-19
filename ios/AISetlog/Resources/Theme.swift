import SwiftUI
import UIKit

/// 1Day's design tokens.
///
/// UIColor is the source of truth (the identity hash in Models needs a color
/// without importing SwiftUI); the SwiftUI colors derive from it. Everything
/// visual in the app resolves back to this file — screens never hardcode a
/// hex, a corner radius, or a shadow.
private extension UIColor {
    static func themed(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }

    /// #1677FF — the one blue everything leans on.
    static let oneDayBlue = UIColor(hex: 0x1677FF)
    /// #38B6FF — the lighter half of the brand gradient.
    static let oneDayCyan = UIColor(hex: 0x38B6FF)
    /// #7FB4FF — tinted rails, inactive strokes, gradient midpoints.
    static let oneDaySky = UIColor(hex: 0x7FB4FF)
    /// #0F2E6B — headline ink in light mode. In dark mode we keep the same
    /// intent with lighter blue so text remains legible.
    static let oneDayNavy = UIColor.themed(
        light: UIColor(hex: 0x0F2E6B),
        dark: UIColor(hex: 0x9AB7FF))
    /// #DCEBFF — soft blue surfaces (chips, icon tiles, empty slots).
    static let oneDayMist = UIColor(hex: 0xDCEBFF)
    /// #F5F8FF — the page behind everything.
    static let oneDayCanvas = UIColor.themed(
        light: UIColor(hex: 0xF5F8FF),
        dark: UIColor(hex: 0x131B2A))
    /// Soft surface token for cards / form fields that used to be white.
    static let oneDaySurface = UIColor.themed(
        light: UIColor(hex: 0xDCEBFF),
        dark: UIColor(hex: 0x171F33))

    // Accents. Used sparingly — one per surface, to keep things cute not busy.
    static let oneDayLavender = UIColor(hex: 0xB3A4FF)
    static let oneDayMint = UIColor(hex: 0x5FD6B4)
    static let oneDayButter = UIColor(hex: 0xFFCE73)
    static let oneDayBlush = UIColor(hex: 0xFF9DB3)
}

extension Color {
    static let oneDayBlue = Color(uiColor: .oneDayBlue)
    static let oneDayCyan = Color(uiColor: .oneDayCyan)
    static let oneDaySky = Color(uiColor: .oneDaySky)
    static let oneDayNavy = Color(uiColor: .oneDayNavy)
    static let oneDayMist = Color(uiColor: .oneDayMist)
    static let oneDayCanvas = Color(uiColor: .oneDayCanvas)
    static let oneDaySurface = Color(uiColor: .oneDaySurface)
    static let oneDayLavender = Color(uiColor: .oneDayLavender)
    static let oneDayMint = Color(uiColor: .oneDayMint)
    static let oneDayButter = Color(uiColor: .oneDayButter)
    static let oneDayBlush = Color(uiColor: .oneDayBlush)
}

/// Semantic tokens. Prefer these over the raw palette in view code: `OneDay.ink`
/// says what the color is *for*, `Color.oneDayNavy` only says what it is.
enum OneDay {
    // MARK: Ink

    static let ink = Color.oneDayNavy
    static let inkSoft = Color(uiColor: UIColor.themed(
        light: UIColor(hex: 0x5B7099),
        dark: UIColor(hex: 0x7E95C5)))
    static let inkFaint = Color(uiColor: UIColor.themed(
        light: UIColor(hex: 0x93A6C6),
        dark: UIColor(hex: 0x657FAF)))

    // MARK: Surfaces

    static let canvas = Color.oneDayCanvas
    /// System-surface-aware card background in light mode and a deep blue in dark
    /// mode so it never turns “gray on gray”.
    static let surface = Color(uiColor: UIColor.themed(
        light: UIColor.white,
        dark: UIColor(hex: 0x171F33)))
    /// Soft fill for chips/cards, now adapted for both modes.
    static let surfaceSoft = Color.oneDaySurface
    /// Hairline border on glass — barely there, just enough to catch an edge.
    static let hairline = Color(uiColor: .themed(
        light: UIColor.oneDayBlue.withAlphaComponent(0.10),
        dark: UIColor.white.withAlphaComponent(0.16)))

    // MARK: Radii
    //
    // Large and consistent. Anything smaller than `chip` reads as a form field
    // rather than a floating object.

    enum Radius {
        static let chip: CGFloat = 14
        static let card: CGFloat = 24
        static let hero: CGFloat = 32
        static let sheet: CGFloat = 36
    }

    // MARK: Layout

    /// Room to leave under any screen inside the Plans stack so content clears
    /// the floating tab bar. The bar is drawn in an overlay above the whole
    /// stack, so a `safeAreaInset` on the shell doesn't reach pushed
    /// destinations — every scrolling screen reserves this itself.
    static let tabBarClearance: CGFloat = 78

    // MARK: Gradients

    static let brand = LinearGradient(
        colors: [Color.oneDayBlue, Color.oneDayCyan],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let brandHorizontal = LinearGradient(
        colors: [Color.oneDayBlue, Color.oneDayCyan],
        startPoint: .leading, endPoint: .trailing)

    /// Behind a cover image, so white text stays legible over any footage.
    static let scrim = LinearGradient(
        colors: [.clear, .black.opacity(0.15), .black.opacity(0.72)],
        startPoint: .top, endPoint: .bottom)

    // MARK: Motion
    //
    // Three curves, used everywhere. `soft` for layout, `pop` for things that
    // appear, `snap` for direct manipulation (carousel, tabs).

    enum Motion {
        static let soft = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let pop = Animation.spring(response: 0.34, dampingFraction: 0.70)
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.86)
    }
}

// MARK: - Shadows

extension View {
    /// Soft ambient lift for a floating card.
    func oneDaySoftShadow(strength: Double = 1) -> some View {
        shadow(color: Color.oneDayNavy.opacity(0.07 * strength), radius: 18 * strength, y: 8 * strength)
    }

    /// Colored lift under a primary action, so the blue feels like it glows.
    func oneDayGlow(_ color: Color = .oneDayBlue, strength: Double = 1) -> some View {
        shadow(color: color.opacity(0.28 * strength), radius: 18 * strength, y: 9 * strength)
    }
}
