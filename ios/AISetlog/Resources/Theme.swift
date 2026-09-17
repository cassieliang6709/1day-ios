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

    /// #1677FF — the blue the app was born in. Pinned, and still the default
    /// accent: caption colours and anything that must stay this exact hue
    /// reads this one rather than `oneDayBrand`.
    static let oneDayBlue = UIColor(hex: 0x1677FF)

    /// The accent the app is currently wearing.
    ///
    /// Your avatar's colour, or the brand blue when you haven't picked one.
    /// Computed rather than stored because it answers a preference, and a
    /// `let` would freeze whichever colour was current at launch.
    ///
    /// Reads the same key the avatar reads, which is the whole point: people
    /// asked for a warm app, and they had already been given a place to say
    /// which colour is theirs. One choice, not two.
    static var oneDayBrand: UIColor { Identity.myPickedUIColor() ?? oneDayBlue }

    /// The lighter end of the brand gradient, derived from whatever the accent
    /// is. Hue rotated a little and saturation eased off — the same
    /// relationship #38B6FF has to #1677FF, applied to any of the seven.
    static var oneDayBrandLight: UIColor {
        let base = oneDayBrand
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard base.getHue(
            &hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        else { return oneDayCyan }
        return UIColor(
            hue: (hue - 0.028 + 1).truncatingRemainder(dividingBy: 1),
            saturation: saturation * 0.84,
            brightness: min(brightness * 1.06, 1),
            alpha: alpha)
    }
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

    // Identity hues. Deeper than the accents above because `AvatarDot` draws a
    // white initial on top — every one of these clears 4:1 against white, which
    // the pastel accents do not (#FFCE73 is 1.8:1). Not interchangeable with
    // them: an accent tints a surface, these carry text.
    /// #E14C3C — 4.0:1 on white.
    static let oneDayCoral = UIColor(hex: 0xE14C3C)
    /// #B5610A — 4.5:1 on white.
    static let oneDayAmber = UIColor(hex: 0xB5610A)
    /// #0E8A5F — 4.3:1 on white. Distinct from `oneDayMint`, which rings "this
    /// is you" — an identity that *was* mint would erase its own ring.
    static let oneDayEmerald = UIColor(hex: 0x0E8A5F)
    /// #6E4FE0 — 5.4:1 on white.
    static let oneDayGrape = UIColor(hex: 0x6E4FE0)
}

extension Color {
    static let oneDayBlue = Color(uiColor: .oneDayBlue)
    /// Computed, not stored, for the same reason as the `UIColor` it wraps: a
    /// `let` here would hand every view the accent as it was at launch.
    static var oneDayBrand: Color { Color(uiColor: .oneDayBrand) }
    static var oneDayBrandLight: Color { Color(uiColor: .oneDayBrandLight) }
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
    static let oneDayCoral = Color(uiColor: .oneDayCoral)
    static let oneDayAmber = Color(uiColor: .oneDayAmber)
    static let oneDayEmerald = Color(uiColor: .oneDayEmerald)
    static let oneDayGrape = Color(uiColor: .oneDayGrape)
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

    static var brand: LinearGradient {
        LinearGradient(
            colors: [Color.oneDayBrand, Color.oneDayBrandLight],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var brandHorizontal: LinearGradient {
        LinearGradient(
            colors: [Color.oneDayBrand, Color.oneDayBrandLight],
            startPoint: .leading, endPoint: .trailing)
    }

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
    func oneDayGlow(_ color: Color = .oneDayBrand, strength: Double = 1) -> some View {
        shadow(color: color.opacity(0.28 * strength), radius: 18 * strength, y: 9 * strength)
    }
}

// MARK: - Caption tints

extension CaptionSticker.Tint {
    /// Deliberately fixed hexes rather than the themed tokens above.
    ///
    /// A caption gets burned into an exported file. Resolving its colour
    /// through `UIColor.themed` would mean the same story exports with dark
    /// ink on a light-mode phone and pale blue on a dark-mode one — the
    /// device's appearance setting deciding what somebody's film looks like
    /// forever. These twelve are pinned values.
    var uiColor: UIColor {
        switch self {
        case .white: .white
        // Not `.black`: a pure black caption on video reads as a hole, and
        // clips to nothing on the darker end of an HDR frame.
        case .black: UIColor(hex: 0x111111)
        case .blue: UIColor(hex: 0x1677FF)
        case .cyan: UIColor(hex: 0x38B6FF)
        case .mint: UIColor(hex: 0x4FD1A5)
        case .butter: UIColor(hex: 0xFFCE73)
        case .coral: UIColor(hex: 0xFF6B4A)
        case .rose: UIColor(hex: 0xE8407A)
        case .lavender: UIColor(hex: 0xB3A4FF)
        case .violet: UIColor(hex: 0x7B5CFF)
        case .blush: UIColor(hex: 0xFF9DB3)
        case .ink: UIColor(hex: 0x0F2E6B)
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

// MARK: - Caption plates

extension CaptionSticker {
    /// The colour of the bar behind the words, or `nil` for the two styles that
    /// have no bar.
    ///
    /// One function for the screen and the exporter, because they have to
    /// agree: the review screen is the only place a caption's look is chosen,
    /// and the film is the only place it matters.
    var plateUIColor: UIColor? {
        guard let plate = style.plate else { return nil }
        // No cleverness here on purpose. An illegible pair — white words on the
        // white bar, black words on the black one — is prevented at the moment
        // it is picked (`CaptionSticker.legible…`), which is the only place a
        // correction can be *seen*. Doing it here instead meant tapping 白底
        // and getting a black bar, with the white square still lit.
        let base: UIColor = plate.isWhite ? .white : UIColor(hex: 0x111111)
        return base.withAlphaComponent(plate.opacity)
    }

    var plateColor: Color? { plateUIColor.map(Color.init(uiColor:)) }
}
