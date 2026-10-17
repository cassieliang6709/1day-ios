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

/// The app's colour skin (1.5). 奶油黄 is the default; 经典蓝 is the blue the
/// app shipped in through 1.4. Picked in Settings → 皮肤.
///
/// Every palette token below is computed and reads `current`, and the app
/// root re-applies `.tint(Color.oneDayBrand)` whenever the setting changes —
/// a new environment value invalidates the whole tree, so every screen
/// re-reads its colours.
enum AppSkin: String, CaseIterable, Identifiable, Codable {
    case cream, blue

    var id: String { rawValue }
    static let storageKey = "appSkin"
    /// Set by Settings when the skin changes; see `AISetlogApp.appSkin`.
    static let reopenSettingsKey = "appSkin.reopenSettings"

    static var current: AppSkin {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppSkin.init) ?? .cream
    }

    var displayName: String {
        switch self {
        case .cream: Strings.skinCream
        case .blue: Strings.skinBlue
        }
    }

    /// The mascot and the logo are pictures, so each skin has its own copy.
    static var mascotImageName: String { current == .cream ? "OneDayMascotCream" : "OneDayMascot" }
    static var lockupImageName: String { current == .cream ? "OneDayBrandLockupCream" : "OneDayBrandLockup" }

    /// The home-screen icon for this skin: `nil` is the primary `AppIcon`,
    /// which is the yellow 奶油黄 icon because that is the default skin — so a
    /// new install never triggers iOS's "icon changed" alert on first launch.
    /// 经典蓝 is the alternate `AppIconBlue` set.
    var alternateIconName: String? { self == .cream ? nil : "AppIconBlue" }

    /// Puts the home-screen icon in line with `skin`. iOS shows an alert on
    /// every icon change, so this only asks when the icon is actually
    /// different; a failure just leaves the old icon.
    @MainActor
    static func syncAppIcon(to skin: AppSkin) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons,
              app.alternateIconName != skin.alternateIconName
        else { return }
        app.setAlternateIconName(skin.alternateIconName) { _ in }
    }
}

extension UIColor {
    /// One colour per skin.
    static func skin(cream: UIColor, blue: UIColor) -> UIColor {
        AppSkin.current == .cream ? cream : blue
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
    static var oneDayBrand: UIColor { skin(cream: oneDayCream, blue: oneDayBlue) }

    /// #FFCB45 — the 奶油黄 skin's accent.
    static let oneDayCream = UIColor(hex: 0xFFCB45)

    /// The lighter end of the brand gradient, derived from the accent rather
    /// than listed: hue rotated a little, saturation eased off — the
    /// relationship #38B6FF has to #1677FF.
    static var oneDayBrandLight: UIColor {
        // 奶油黄: a paler butter rather than a hue rotation, which on yellow
        // lands on orange.
        if oneDayBrand == oneDayCream { return UIColor(hex: 0xFFE08A) }
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
    static var oneDayCyan: UIColor { skin(cream: UIColor(hex: 0xFFB86B), blue: UIColor(hex: 0x38B6FF)) }
    /// #7FB4FF — tinted rails, inactive strokes, gradient midpoints.
    static var oneDaySky: UIColor { skin(cream: UIColor(hex: 0xFFD98A), blue: UIColor(hex: 0x7FB4FF)) }
    /// #0F2E6B — headline ink in light mode. In dark mode we keep the same
    /// intent with lighter blue so text remains legible.
    static var oneDayNavy: UIColor {
        skin(
            cream: .themed(light: UIColor(hex: 0x3A2B1B), dark: UIColor(hex: 0xF3E3C3)),
            blue: .themed(light: UIColor(hex: 0x0F2E6B), dark: UIColor(hex: 0x9AB7FF)))
    }
    /// #DCEBFF — soft blue surfaces (chips, icon tiles, empty slots).
    ///
    /// Themed since 1.4. It used to be a fixed hex, so in dark mode a sheet
    /// backed with it (`ClipPreviewView`'s look picker) was a pale-blue slab
    /// under light-blue ink, and every tile tinted with it glowed. Dark keeps
    /// the "a step up from the page" intent with the same deep blue as
    /// `oneDaySurface`. The canvas blooms opt out explicitly — they pass their
    /// own dark colour — so nothing decorative changed.
    static var oneDayMist: UIColor {
        skin(
            cream: .themed(light: UIColor(hex: 0xFFF1CC), dark: UIColor(hex: 0x3A2F22)),
            blue: .themed(light: UIColor(hex: 0xDCEBFF), dark: UIColor(hex: 0x22304D)))
    }
    /// #F5F8FF — the page behind everything.
    static var oneDayCanvas: UIColor {
        skin(
            cream: .themed(light: UIColor(hex: 0xFFF8E8), dark: UIColor(hex: 0x1E1912)),
            blue: .themed(light: UIColor(hex: 0xF5F8FF), dark: UIColor(hex: 0x131B2A)))
    }
    /// Soft surface token for cards / form fields that used to be white.
    ///
    /// Dark is #22304D, not the #171F33 it used to share with `OneDay.surface`:
    /// a soft chip inside a card was the same colour as the card, so the chip
    /// simply vanished. One clear step lighter than the card, the way the
    /// light pair (#DCEBFF on white) already worked.
    static var oneDaySurface: UIColor {
        skin(
            cream: .themed(light: UIColor(hex: 0xFFF1CC), dark: UIColor(hex: 0x3A2F22)),
            blue: .themed(light: UIColor(hex: 0xDCEBFF), dark: UIColor(hex: 0x22304D)))
    }

    // Accents. Used sparingly — one per surface, to keep things cute not busy.
    static let oneDayLavender = UIColor(hex: 0xB3A4FF)
    static let oneDayMint = UIColor(hex: 0x5FD6B4)
    static let oneDayButter = UIColor(hex: 0xFFCE73)
    static let oneDayBlush = UIColor(hex: 0xFF9DB3)

    // Status hues — warm, text-capable, *not* identities. Kept because screens
    // use them for meaning (an error line, a pending badge), not for people.
    /// #B5610A — 4.5:1 on white. Pending / attention.
    static let oneDayAmber = UIColor(hex: 0xB5610A)
    /// #C34B18 — 4.8:1. Error text.
    static let oneDayEmber = UIColor(hex: 0xC34B18)

    // Identity hues. Eight, down from twelve, and every one a *fixed* hex.
    //
    // Fixed because an avatar is a person, not chrome: the old palette led
    // with `oneDayNavy`, which is themed, so in dark mode the first identity
    // turned #9AB7FF and the white initial on it fell to 1.98:1. A person
    // should also be the same colour on your phone and on a friend's,
    // whatever either of you set Appearance to.
    //
    // Eight because twelve could not be told apart. Blue vs Steel and Peacock
    // vs Emerald were near-duplicates to anyone, and Amber/Ember/Mustard/Moss
    // collapsed into one brown under deuteranopia (~6% of men). These were
    // chosen by search, not by eye: each clears 4.5:1 with white text, and
    // every pair is at least ΔE 20 (CIELAB) apart under normal vision *and*
    // simulated deuteranopia and protanopia. Where hue can't separate two
    // (green/rose, amber/rose under CVD) lightness does — L* runs 21–49.
    //
    // Not interchangeable with the pastel accents above: an accent tints a
    // surface, these carry text. `oneDayMint` stays out — it rings "this is
    // you", and an identity that *was* mint would erase its own ring.
    /// #0F2E6B — 12.9:1. The light-mode ink, pinned so it never lightens.
    static let identityNavy = UIColor(hex: 0x0F2E6B)
    /// #3167B6 — 5.6:1. The brand blue deepened: #1677FF itself is 4.1:1.
    static let identityBlue = UIColor(hex: 0x3167B6)
    /// #007F91 — 4.7:1. Teal, light end, so it doesn't sit on the graphite.
    static let identityTeal = UIColor(hex: 0x007F91)
    /// #18652E — 7.1:1. Green kept dark so it parts from the rose under CVD.
    static let identityGreen = UIColor(hex: 0x18652E)
    /// #AD6102 — 4.7:1. The only warm-yellow; the light end of the band.
    static let identityAmber = UIColor(hex: 0xAD6102)
    /// #E00B4C — 4.9:1. The loudest of the eight.
    static let identityRose = UIColor(hex: 0xE00B4C)
    /// #6E12C6 — 8.2:1. Violet, pushed away from blue in both hue and depth.
    static let identityGrape = UIColor(hex: 0x6E12C6)
    /// #343F50 — 10.6:1. Near-neutral slate, for somebody who doesn't want a
    /// colour. Dark so it separates from the teal (they share a grey under
    /// deuteranopia at equal lightness).
    static let identityGraphite = UIColor(hex: 0x343F50)
}

extension Color {
    static let oneDayBlue = Color(uiColor: .oneDayBlue)
    /// Computed, not stored, for the same reason as the `UIColor` it wraps: a
    /// `let` here would hand every view the accent as it was at launch.
    static var oneDayBrand: Color { Color(uiColor: .oneDayBrand) }
    static var oneDayBrandLight: Color { Color(uiColor: .oneDayBrandLight) }
    static var oneDayCyan: Color { Color(uiColor: .oneDayCyan) }
    static var oneDaySky: Color { Color(uiColor: .oneDaySky) }
    static var oneDayNavy: Color { Color(uiColor: .oneDayNavy) }
    static var oneDayMist: Color { Color(uiColor: .oneDayMist) }
    static var oneDayCanvas: Color { Color(uiColor: .oneDayCanvas) }
    static var oneDaySurface: Color { Color(uiColor: .oneDaySurface) }
    static let oneDayLavender = Color(uiColor: .oneDayLavender)
    static let oneDayMint = Color(uiColor: .oneDayMint)
    static let oneDayButter = Color(uiColor: .oneDayButter)
    static let oneDayBlush = Color(uiColor: .oneDayBlush)
    static let oneDayAmber = Color(uiColor: .oneDayAmber)
    static let oneDayEmber = Color(uiColor: .oneDayEmber)
    // No `Color` twins for the identity hues: views reach them through
    // `Identity.tint(for:)`, which is what keeps a person one colour.
}

/// Semantic tokens. Prefer these over the raw palette in view code: `OneDay.ink`
/// says what the color is *for*, `Color.oneDayNavy` only says what it is.
enum OneDay {
    // MARK: Ink

    static var ink: Color { Color.oneDayNavy }
    static var inkSoft: Color {
        Color(uiColor: .skin(
            cream: .themed(light: UIColor(hex: 0x7A6650), dark: UIColor(hex: 0xC9B593)),
            blue: .themed(light: UIColor(hex: 0x5B7099), dark: UIColor(hex: 0x7E95C5))))
    }
    /// The quietest ink — timestamps, placeholders, "optional".
    ///
    /// Light was #93A6C6 until 1.4, which is 2.47:1 on white: decorative,
    /// not text. #6F84A8 is 3.8:1 — enough for the secondary, never-essential
    /// copy this is for, while staying visibly a step below `inkSoft`. Anything
    /// a user needs to read to act (a section heading, a label) takes
    /// `inkSoft` instead.
    static var inkFaint: Color {
        Color(uiColor: .skin(
            cream: .themed(light: UIColor(hex: 0x8F7C66), dark: UIColor(hex: 0xA08D70)),
            blue: .themed(light: UIColor(hex: 0x6F84A8), dark: UIColor(hex: 0x657FAF))))
    }

    /// Brand blue for *text* under 18pt.
    ///
    /// #1677FF is 4.1:1 on white — fine for a filled button, a ring or a
    /// large headline, short of 4.5:1 for small type. #0F62D6 (5.6:1) reads
    /// as the same blue at caption size. Dark mode lifts it to #8CB8FF
    /// (8.6:1 on the canvas), because the raw brand blue on #131B2A is 4.2:1.
    /// Fills and glows keep `Color.oneDayBrand`; only letters use this.
    ///
    /// 奶油黄 can't be text at all — #FFCB45 on white is 1.5:1 — so its
    /// letters are a deep amber (#8A5A00, 5.9:1).
    static var brandText: Color {
        Color(uiColor: .skin(
            cream: .themed(light: UIColor(hex: 0x8A5A00), dark: UIColor(hex: 0xFFD66B)),
            blue: .themed(light: UIColor(hex: 0x0F62D6), dark: UIColor(hex: 0x8CB8FF))))
    }

    /// Letters and glyphs drawn *on* a brand fill — the primary button, the
    /// selected tab, the camera disc. White on blue; on 奶油黄 white is
    /// unreadable, so a deep brown that works in both appearances.
    static var onBrand: Color {
        Color(uiColor: .skin(cream: UIColor(hex: 0x3A2B1B), blue: .white))
    }

    // MARK: Surfaces

    static var canvas: Color { Color.oneDayCanvas }
    /// System-surface-aware card background in light mode and a deep blue in dark
    /// mode so it never turns “gray on gray”.
    static var surface: Color {
        Color(uiColor: .skin(
            cream: .themed(light: .white, dark: UIColor(hex: 0x2A2219)),
            blue: .themed(light: .white, dark: UIColor(hex: 0x171F33))))
    }
    /// Soft fill for chips/cards, now adapted for both modes.
    static var surfaceSoft: Color { Color.oneDaySurface }
    /// Hairline border on glass — barely there, just enough to catch an edge.
    static var hairline: Color {
        Color(uiColor: .themed(
            light: UIColor.skin(cream: UIColor(hex: 0x3A2B1B), blue: .oneDayBlue).withAlphaComponent(0.10),
            dark: UIColor.white.withAlphaComponent(0.16)))
    }

    // MARK: Radii
    //
    // Large and consistent. Anything smaller than `chip` reads as a form field
    // rather than a floating object.

    enum Radius {
        static let chip: CGFloat = 14
        static let card: CGFloat = 24
        static let hero: CGFloat = 32
    }

    // MARK: Type
    //
    // Text styles, not point sizes, so everything scales with Dynamic Type.
    // `.system(size:)` is pinned: a user who sets Larger Text got bigger
    // Settings and the same tiny 12pt chips. Each token is the nearest system
    // style to the size the design used, in the app's rounded face, so at the
    // default setting the screen looks as it did and at AX5 it grows with
    // everything else.
    //
    //   title     22pt  .title2    screen and sheet titles
    //   headline  17pt  .headline  primary action labels, card titles
    //   body      17pt  .body      running copy
    //   callout   16pt  .callout   row titles, secondary buttons
    //   subhead   15pt  .subheadline  segment labels, list detail
    //   caption   12pt  .caption   chips, section labels, metadata
    //   micro     11pt  .caption2  timecodes, badges
    //
    // Icons inside a control use the same tokens (an SF Symbol sizes from
    // its font), so a glyph grows with the label beside it.

    enum Font {
        static let title = SwiftUI.Font.system(.title2, design: .rounded, weight: .bold)
        static let headline = SwiftUI.Font.system(.headline, design: .rounded, weight: .bold)
        static let body = SwiftUI.Font.system(.body, design: .rounded)
        static let callout = SwiftUI.Font.system(.callout, design: .rounded, weight: .semibold)
        static let subhead = SwiftUI.Font.system(.subheadline, design: .rounded, weight: .semibold)
        static let caption = SwiftUI.Font.system(.caption, design: .rounded, weight: .semibold)
        static let micro = SwiftUI.Font.system(.caption2, design: .rounded, weight: .semibold)

        /// Any style at any weight, still rounded and still scaling — for the
        /// call site that needs `caption` but bold.
        static func rounded(
            _ style: SwiftUI.Font.TextStyle, weight: SwiftUI.Font.Weight = .semibold
        ) -> SwiftUI.Font {
            .system(style, design: .rounded, weight: weight)
        }
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

        /// The curve to use when Reduce Motion may be on.
        ///
        /// Springs that move a view a few points are fine under Reduce Motion
        /// — it is about *ongoing* or large movement — but anything that
        /// loops (`repeatForever`) or zooms has to stop. Pass the environment
        /// value in; returning `nil` makes `withAnimation` / `.animation`
        /// apply the change instantly:
        ///
        ///     @Environment(\.accessibilityReduceMotion) private var reduceMotion
        ///     .animation(OneDay.Motion.reduced(.pulse, if: reduceMotion), value: x)
        static func reduced(_ animation: Animation, if reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }

        /// The slow breathe the mascot does while it works. Loops, so it must
        /// only ever be used through `reduced(_:if:)`.
        static let pulse = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    }
}

// MARK: - Shadows

/// Navy ink in light mode, black in dark.
///
/// The soft shadow used to be `oneDayNavy` at 7%, and `oneDayNavy` is themed:
/// in dark mode it is #9AB7FF, so every card cast a faint *light-blue* halo —
/// a glow, not a shadow. Dark needs black, and a lot more of it, because a
/// shadow on #131B2A has almost nothing to darken.
private struct OneDaySoftShadow: ViewModifier {
    let strength: Double
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let color = isDark
            ? Color.black.opacity(0.32 * strength)
            : Color(uiColor: .identityNavy).opacity(0.07 * strength)
        return content.shadow(color: color, radius: 18 * strength, y: 8 * strength)
    }
}

extension View {
    /// Soft ambient lift for a floating card.
    func oneDaySoftShadow(strength: Double = 1) -> some View {
        modifier(OneDaySoftShadow(strength: strength))
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
