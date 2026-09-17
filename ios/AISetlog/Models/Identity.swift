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

    /// Which of the seven you picked for yourself, and the name it was picked
    /// under. Two keys rather than one because the palette is addressed by
    /// name everywhere — every avatar in the app is drawn from a name and
    /// nothing else — so the override has to know which name is yours.
    static let myTintKey = "identity.myTint.v1"
    static let myTintNameKey = "identity.myTintName.v1"

    /// Your own colour, from now on, on this device.
    ///
    /// Stored rather than derived, and stored against the name so renaming
    /// yourself doesn't silently hand your colour to whoever is called that
    /// next. Passing `nil` goes back to the derived one.
    static func chooseTint(
        _ index: Int?, forName name: String?,
        in defaults: UserDefaults = .standard
    ) {
        guard let index, let name, !name.isEmpty, paletteUIColors.indices.contains(index)
        else {
            defaults.removeObject(forKey: myTintKey)
            defaults.removeObject(forKey: myTintNameKey)
            return
        }
        defaults.set(index, forKey: myTintKey)
        defaults.set(name, forKey: myTintNameKey)
    }

    /// The index your own avatar is currently drawn with, picked or derived.
    static func tintIndex(for name: String?, in defaults: UserDefaults = .standard) -> Int {
        if let name, !name.isEmpty,
           name == defaults.string(forKey: myTintNameKey),
           let picked = defaults.object(forKey: myTintKey) as? Int,
           paletteUIColors.indices.contains(picked) {
            return picked
        }
        return derivedIndex(for: name)
    }

    /// The old rule, unchanged: it still draws everybody else.
    ///
    /// Two people can now land on the same colour — one by hash, one by
    /// choice — which is allowed. Telling people apart in a room was never
    /// only the colour's job; the name is under every avatar.
    static func derivedIndex(for name: String?) -> Int {
        guard let name, !name.isEmpty else { return 1 }
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % paletteUIColors.count
    }

    static func uiColor(for name: String?) -> UIColor {
        guard let name, !name.isEmpty else { return .oneDayBlue }
        return paletteUIColors[tintIndex(for: name)]
    }
    /// An absent name has no text fallback; views use the mascot artwork for
    /// that state so the retired "1D" initials never return as a brand mark.
    static func initial(for name: String?) -> String {
        guard let name, let first = name.first else { return "" }
        return String(first).uppercased()
    }
}
