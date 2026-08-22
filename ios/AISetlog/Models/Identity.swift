import UIKit

/// A stable visual identity (color + initial) derived from a recorder's
/// name — used to tell whose clip is whose in a shared room, instead of the
/// old free-choice "sticker pack". `MemberChip` (ChallengeBoardView) shares
/// this same palette so a person's color matches everywhere in the app.
enum Identity {
    static let paletteUIColors: [UIColor] = [
        .oneDayNavy, .oneDayBlue, .oneDayCyan,
        .oneDaySky, .systemTeal, .systemBlue,
    ]

    static func uiColor(for name: String?) -> UIColor {
        guard let name, !name.isEmpty else { return .oneDayBlue }
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return paletteUIColors[sum % paletteUIColors.count]
    }
    /// An absent name has no text fallback; views use the mascot artwork for
    /// that state so the retired "1D" initials never return as a brand mark.
    static func initial(for name: String?) -> String {
        guard let name, let first = name.first else { return "" }
        return String(first).uppercased()
    }
}
