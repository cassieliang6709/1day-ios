import SwiftUI
import UIKit

private extension UIColor {
    static func themed(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

enum AppSkin: String, CaseIterable, Identifiable, Codable {
    case cream, blue

    var id: String { rawValue }
    static let storageKey = "appSkin"
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

    static var mascotImageName: String { current == .cream ? "OneDayMascotCream" : "OneDayMascot" }
    static var lockupImageName: String { current == .cream ? "OneDayBrandLockupCream" : "OneDayBrandLockup" }

    var alternateIconName: String? { self == .cream ? nil : "AppIconBlue" }

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

    static let oneDayBlue = UIColor(hex: 0x1677FF)

    static var oneDayBrand: UIColor { skin(cream: oneDayCream, blue: oneDayBlue) }

    static let oneDayCream = UIColor(hex: 0xFFCB45)

    static var oneDayBrandLight: UIColor {
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
    static var oneDayCyan: UIColor { skin(cream: UIColor(hex: 0xFFB86B), blue: UIColor(hex: 0x38B6FF)) }
    static var oneDaySky: UIColor { skin(cream: UIColor(hex: 0xFFD98A), blue: UIColor(hex: 0x7FB4FF)) }
    static var oneDayNavy: UIColor {
        skin(
            cream: .themed(light: UIColor(hex: 0x3A2B1B), dark: UIColor(hex: 0xF3E3C3)),
            blue: .themed(light: UIColor(hex: 0x0F2E6B), dark: UIColor(hex: 0x9AB7FF)))
    }
    static var oneDayMist: UIColor {
        skin(
            cream: .themed(light: UIColor(hex: 0xFFF1CC), dark: UIColor(hex: 0x3A2F22)),
            blue: .themed(light: UIColor(hex: 0xDCEBFF), dark: UIColor(hex: 0x22304D)))
    }
    static var oneDayCanvas: UIColor {
        skin(
            cream: .themed(light: UIColor(hex: 0xFFF8E8), dark: UIColor(hex: 0x1E1912)),
            blue: .themed(light: UIColor(hex: 0xF5F8FF), dark: UIColor(hex: 0x131B2A)))
    }
    static var oneDaySurface: UIColor {
        skin(
            cream: .themed(light: UIColor(hex: 0xFFF1CC), dark: UIColor(hex: 0x3A2F22)),
            blue: .themed(light: UIColor(hex: 0xDCEBFF), dark: UIColor(hex: 0x22304D)))
    }

    static let oneDayLavender = UIColor(hex: 0xB3A4FF)
    static let oneDayMint = UIColor(hex: 0x5FD6B4)
    static let oneDayButter = UIColor(hex: 0xFFCE73)
    static let oneDayBlush = UIColor(hex: 0xFF9DB3)

    static let oneDayAmber = UIColor(hex: 0xB5610A)
    static let oneDayEmber = UIColor(hex: 0xC34B18)

    static let identityNavy = UIColor(hex: 0x0F2E6B)
    static let identityBlue = UIColor(hex: 0x3167B6)
    static let identityTeal = UIColor(hex: 0x007F91)
    static let identityGreen = UIColor(hex: 0x18652E)
    static let identityAmber = UIColor(hex: 0xAD6102)
    static let identityRose = UIColor(hex: 0xE00B4C)
    static let identityGrape = UIColor(hex: 0x6E12C6)
    static let identityGraphite = UIColor(hex: 0x343F50)
}

extension Color {
    static let oneDayBlue = Color(uiColor: .oneDayBlue)
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
}

enum OneDay {

    static var ink: Color { Color.oneDayNavy }
    static var inkSoft: Color {
        Color(uiColor: .skin(
            cream: .themed(light: UIColor(hex: 0x7A6650), dark: UIColor(hex: 0xC9B593)),
            blue: .themed(light: UIColor(hex: 0x5B7099), dark: UIColor(hex: 0x7E95C5))))
    }
    static var inkFaint: Color {
        Color(uiColor: .skin(
            cream: .themed(light: UIColor(hex: 0x8F7C66), dark: UIColor(hex: 0xA08D70)),
            blue: .themed(light: UIColor(hex: 0x6F84A8), dark: UIColor(hex: 0x657FAF))))
    }

    static var brandText: Color {
        Color(uiColor: .skin(
            cream: .themed(light: UIColor(hex: 0x8A5A00), dark: UIColor(hex: 0xFFD66B)),
            blue: .themed(light: UIColor(hex: 0x0F62D6), dark: UIColor(hex: 0x8CB8FF))))
    }

    static var onBrand: Color {
        Color(uiColor: .skin(cream: UIColor(hex: 0x3A2B1B), blue: .white))
    }


    static var canvas: Color { Color.oneDayCanvas }
    static var surface: Color {
        Color(uiColor: .skin(
            cream: .themed(light: .white, dark: UIColor(hex: 0x2A2219)),
            blue: .themed(light: .white, dark: UIColor(hex: 0x171F33))))
    }
    static var surfaceSoft: Color { Color.oneDaySurface }
    static var hairline: Color {
        Color(uiColor: .themed(
            light: UIColor.skin(cream: UIColor(hex: 0x3A2B1B), blue: .oneDayBlue).withAlphaComponent(0.10),
            dark: UIColor.white.withAlphaComponent(0.16)))
    }


    enum Radius {
        static let chip: CGFloat = 14
        static let card: CGFloat = 24
        static let hero: CGFloat = 32
        static let tile: CGFloat = 12
    }


    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }


    enum Font {
        static let title = SwiftUI.Font.system(.title2, design: .rounded, weight: .bold)
        static let headline = SwiftUI.Font.system(.headline, design: .rounded, weight: .bold)
        static let body = SwiftUI.Font.system(.body, design: .rounded)
        static let callout = SwiftUI.Font.system(.callout, design: .rounded, weight: .semibold)
        static let subhead = SwiftUI.Font.system(.subheadline, design: .rounded, weight: .semibold)
        static let caption = SwiftUI.Font.system(.caption, design: .rounded, weight: .semibold)
        static let micro = SwiftUI.Font.system(.caption2, design: .rounded, weight: .semibold)

        static func rounded(
            _ style: SwiftUI.Font.TextStyle, weight: SwiftUI.Font.Weight = .semibold
        ) -> SwiftUI.Font {
            .system(style, design: .rounded, weight: weight)
        }
    }


    static let tabBarClearance: CGFloat = 78


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

    static let scrim = LinearGradient(
        colors: [.clear, .black.opacity(0.15), .black.opacity(0.72)],
        startPoint: .top, endPoint: .bottom)


    enum Motion {
        static let soft = Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let pop = Animation.spring(response: 0.34, dampingFraction: 0.70)
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.86)

        static func reduced(_ animation: Animation, if reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }

        static let pulse = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    }
}


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
    func oneDaySoftShadow(strength: Double = 1) -> some View {
        modifier(OneDaySoftShadow(strength: strength))
    }

    func oneDayGlow(_ color: Color = .oneDayBrand, strength: Double = 1) -> some View {
        shadow(color: color.opacity(0.28 * strength), radius: 18 * strength, y: 9 * strength)
    }
}


extension CaptionSticker.Tint {
    var uiColor: UIColor {
        switch self {
        case .white: .white
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


extension CaptionSticker {
    var plateUIColor: UIColor? {
        guard let plate = style.plate else { return nil }
        let base: UIColor = plate.isWhite ? .white : UIColor(hex: 0x111111)
        return base.withAlphaComponent(plate.opacity)
    }

    var plateColor: Color? { plateUIColor.map(Color.init(uiColor:)) }
}
