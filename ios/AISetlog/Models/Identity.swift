import UIKit

/// A stable visual identity (color + initial) derived from a recorder's
/// name — used to tell whose clip is whose in a shared room, instead of the
/// old free-choice "sticker pack". `MemberChip` (ChallengeBoardView) shares
/// this same palette so a person's color matches everywhere in the app.
enum Identity {
    /// Twelve hues, spread across the wheel, in the order the picker draws them.
    ///
    /// This is also the app's accent palette (`UIColor.oneDayBrand`), so every
    /// entry has to carry white text twice over: the initial `AvatarDot` draws
    /// on it, and the label on a filled button. The bar is 4:1 and these were
    /// picked by measuring, not by eye — which is how two of the previous seven
    /// turned out to be under it. `oneDayCyan` was **2.26:1**, and the comment
    /// here used to claim all seven cleared 4:1; `oneDayCoral` was 3.96:1.
    /// Both are replaced (`oneDaySteel`, `oneDayEmber`) rather than kept at a
    /// size where nobody can read their own initial.
    ///
    /// `oneDayMint` is not a candidate: it rings "this is you" in `AvatarStack`.
    ///
    /// Growing the list from seven to twelve moves everybody's *derived*
    /// colour, because that is `sum % count`. Unavoidable when the palette
    /// changes size, and only affects people who never picked one — a pick is
    /// stored by name and survives.
    static let paletteUIColors: [UIColor] = [
        .oneDayNavy, .oneDayBlue, .oneDaySteel, .oneDayPeacock,
        .oneDayEmerald, .oneDayMoss, .oneDayMustard, .oneDayAmber,
        .oneDayEmber, .oneDayRose, .oneDayGraphite, .oneDayGrape,
    ]

    /// Which of the twelve you picked for yourself, and the name it was picked
    /// under. Two keys rather than one because the palette is addressed by
    /// name everywhere — every avatar in the app is drawn from a name and
    /// nothing else — so the override has to know which name is yours.
    ///
    /// Read only by `tintIndex(for:)`. The app's accent used to read them too;
    /// it no longer does — see `UIColor.oneDayBrand`.
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
        // 1 is the brand blue's slot: a nameless avatar draws the mascot, and
        // anything else reading this wants the app's own colour.
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
