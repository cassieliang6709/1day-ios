import Foundation
import SwiftUI

/// A stable visual identity (color + initial) derived from a recorder's
/// name — used to tell whose clip is whose in a shared room, instead of the
/// old free-choice "sticker pack". `MemberChip` (ChallengeBoardView) shares
/// this same palette so a person's color matches everywhere in the app.
enum Identity {
    static let paletteUIColors: [UIColor] = [
        UIColor(Color.oneDayNavy), UIColor(Color.oneDayBlue), UIColor(Color.oneDayCyan),
        UIColor(Color.oneDaySky), .systemTeal, .systemBlue,
    ]

    static func uiColor(for name: String?) -> UIColor {
        guard let name, !name.isEmpty else { return UIColor(Color.oneDayBlue) }
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return paletteUIColors[sum % paletteUIColors.count]
    }

    static func tint(for name: String?) -> Color {
        Color(uiColor: uiColor(for: name))
    }

    /// Falls back to the app's brand mark when there's no one to identify
    /// (a solo challenge has no recorded author).
    static func initial(for name: String?) -> String {
        guard let name, let first = name.first else { return "1D" }
        return String(first).uppercased()
    }
}
