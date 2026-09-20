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

    /// #1677FF — the blue the app was born in, and the only accent it wears.
    static let oneDayBlue = UIColor(hex: 0x1677FF)

    /// The app's accent. Always the brand blue.
    ///
    /// This used to read the colour you picked for your avatar, on the theory
    /// that one choice should do both jobs. It does not: the canvas, the
    /// mascot and the illustrated covers are all cool blues and cannot be
    /// re-tinted, so choosing pink painted pink buttons onto a blue app and
    /// the two fought on every screen.
    ///
    /// Picking a colour still works — it just colours your avatar now, which
    /// is the job it was added for and the one place a warm colour has nothing
    /// to clash with. See `Identity.color(for:)`.
    ///
    /// Kept as a property rather than folded into the 119 call sites: it is
    /// the seam that made turning this off a one-line change, and it would be
    /// the seam again if themes ever come back properly.
    static var oneDayBrand: UIColor { oneDayBlue }

    /// The lighter end of the brand gradient, derived from the accent rather
    /// than listed: hue rotated a little, saturation eased off — the
    /// relationship #38B6FF has to #1677FF.
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
    /// #1678B1 — 4.8:1. Replaces `oneDayCyan` in the identity palette: that
    /// one is 2.26:1 against white, so the initial drawn on it was a smudge
    /// and so was every button label once the accent followed it.
    static let oneDaySteel = UIColor(hex: 0x1678B1)
    /// #107C84 — 5.0:1. Between the blue and the green, so a room of four
    /// people doesn't read as three blues.
    static let oneDayPeacock = UIColor(hex: 0x107C84)
    /// #4B7F10 — 4.8:1. The yellow end of green.
    static let oneDayMoss = UIColor(hex: 0x4B7F10)
    /// #8A710F — 4.7:1. Warm without being orange.
    static let oneDayMustard = UIColor(hex: 0x8A710F)
    /// #C34B18 — 4.8:1. `oneDayCoral` at 3.96:1 was just under the line.
    static let oneDayEmber = UIColor(hex: 0xC34B18)
    /// #DA1B4E — 4.9:1. The loudest of the twelve.
    static let oneDayRose = UIColor(hex: 0xDA1B4E)
    /// #5A6C8C — 5.3:1. Near-neutral, for somebody who doesn't want a colour.
    static let oneDayGraphite = UIColor(hex: 0x5A6C8C)
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
    static let oneDaySteel = Color(uiColor: .oneDaySteel)
    static let oneDayPeacock = Color(uiColor: .oneDayPeacock)
    static let oneDayMoss = Color(uiColor: .oneDayMoss)
    static let oneDayMustard = Color(uiColor: .oneDayMustard)
    static let oneDayEmber = Color(uiColor: .oneDayEmber)
    static let oneDayRose = Color(uiColor: .oneDayRose)
    static let oneDayGraphite = Color(uiColor: .oneDayGraphite)
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
