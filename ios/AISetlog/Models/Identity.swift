import UIKit

/// A stable visual identity (color + initial) derived from a recorder's
/// name — used to tell whose clip is whose in a shared room, instead of the
/// old free-choice "sticker pack". Every avatar, byline and timeline node
/// reads this same palette so a person's color matches everywhere in the app.
enum Identity {
    /// Eight hues, in the order the picker draws them.
    ///
    /// White text has to sit on every entry — the initial `AvatarDot` draws —
    /// so each clears 4.5:1 against white, measured rather than eyeballed
    /// (an earlier comment here claimed 4:1 for a list containing a 2.26:1
    /// cyan). They are also *fixed* hexes: a person is not chrome, and must
    /// not change colour with the viewer's Appearance setting. Why these eight
    /// and not the previous twelve is written up next to the hexes in
    /// `Resources/Theme.swift` — short version, four pairs of the twelve were
    /// indistinguishable, two of them to everyone.
    ///
    /// `oneDayMint` is not a candidate: it rings "this is you" in `AvatarStack`.
    ///
    /// Shrinking the list moves everybody's *derived* colour, because that is
    /// `sum % count`. Unavoidable when the palette changes size, and only
    /// affects people who never picked one — a pick is carried across by
    /// `legacyTintRemap`.
    static let paletteUIColors: [UIColor] = [
        .identityNavy, .identityBlue, .identityTeal, .identityGreen,
        .identityAmber, .identityRose, .identityGrape, .identityGraphite,
    ]

    /// Which of the eight you picked for yourself, and the name it was picked
    /// under. Two keys rather than one because the palette is addressed by
    /// name everywhere — every avatar in the app is drawn from a name and
    /// nothing else — so the override has to know which name is yours.
    ///
    /// The index key is `v2` because the palette it indexes changed: a `v1`
    /// index meant a slot in the twelve, and reading it against the eight
    /// would quietly hand somebody who chose rose (old 9) nothing at all, or
    /// somebody who chose emerald (old 4) amber. The name key didn't change
    /// meaning, so it keeps its name.
    ///
    /// Read only by `tintIndex(for:)`. The app's accent used to read them too;
    /// it no longer does — see `UIColor.oneDayBrand`.
    static let myTintKey = "identity.myTint.v2"
    static let myTintNameKey = "identity.myTintName.v1"
    /// Where a pick made against the twelve-colour palette lives. Read, never
    /// written; cleared the first time you pick again.
    static let legacyTintKey = "identity.myTint.v1"

    /// Old twelve-colour slot → nearest of the eight. Explicit rather than
    /// `% count`, which would map a rose pick onto green.
    ///
    ///   0 navy → navy      4 emerald → green    8 ember    → amber
    ///   1 blue → blue      5 moss    → green    9 rose     → rose
    ///   2 steel → blue     6 mustard → amber   10 graphite → graphite
    ///   3 peacock → teal   7 amber   → amber   11 grape    → grape
    static let legacyTintRemap: [Int] = [0, 1, 1, 2, 3, 3, 4, 4, 4, 5, 7, 6]

    /// Your own colour, from now on, on this device.
    ///
    /// Stored rather than derived, and stored against the name so renaming
    /// yourself doesn't silently hand your colour to whoever is called that
    /// next. Passing `nil` goes back to the derived one.
    static func chooseTint(
        _ index: Int?, forName name: String?,
        in defaults: UserDefaults = .standard
    ) {
        // Any write supersedes a pick made against the old palette.
        defaults.removeObject(forKey: legacyTintKey)
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
        guard let name, !name.isEmpty, name == defaults.string(forKey: myTintNameKey)
        else { return derivedIndex(for: name) }
        // Anything out of range — a corrupted value, or one from a build with
        // a longer palette — falls back to derived rather than indexing past
        // the end.
        if let picked = defaults.object(forKey: myTintKey) as? Int {
            return paletteUIColors.indices.contains(picked) ? picked : derivedIndex(for: name)
        }
        if let legacy = defaults.object(forKey: legacyTintKey) as? Int,
           legacyTintRemap.indices.contains(legacy) {
            return legacyTintRemap[legacy]
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
        // `%` as a last guard: `tintIndex` already range-checks, but this is
        // the one subscript in the app that a stored value reaches.
        return paletteUIColors[tintIndex(for: name) % paletteUIColors.count]
    }
    /// An absent name has no text fallback; views use the mascot artwork for
    /// that state so the retired "1D" initials never return as a brand mark.
    static func initial(for name: String?) -> String {
        guard let name, let first = name.first else { return "" }
        return String(first).uppercased()
    }
}
