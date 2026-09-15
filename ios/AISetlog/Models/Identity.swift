import UIKit

/// A stable visual identity (color + initial) derived from a recorder's
/// name — used to tell whose clip is whose in a shared room, instead of the
/// old free-choice "sticker pack". `MemberChip` (ChallengeBoardView) shares
/// this same palette so a person's color matches everywhere in the app.
enum Identity {
    /// Seven hues, deliberately spread across the wheel. The old palette was six
    /// blues (`oneDaySky`, `systemTeal`, `systemBlue` among them), so two people
    /// in one room read as the same person at a glance — and the light end of it
    /// could not hold the white initial `AvatarDot` draws on top. Every entry
    /// here clears 4:1 against white.
    ///
    /// `oneDayMint` is not a candidate: it rings "this is you" in `AvatarStack`.
    static let paletteUIColors: [UIColor] = [
        .oneDayNavy, .oneDayBlue, .oneDayCyan,
        .oneDayCoral, .oneDayAmber, .oneDayEmerald, .oneDayGrape,
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
