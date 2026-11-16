import UIKit

enum Identity {
    static let paletteUIColors: [UIColor] = [
        .identityNavy, .identityBlue, .identityTeal, .identityGreen,
        .identityAmber, .identityRose, .identityGrape, .identityGraphite,
    ]

    static let myTintKey = "identity.myTint.v2"
    static let myTintNameKey = "identity.myTintName.v1"
    static let legacyTintKey = "identity.myTint.v1"

    static let legacyTintRemap: [Int] = [0, 1, 1, 2, 3, 3, 4, 4, 4, 5, 7, 6]

    static func chooseTint(
        _ index: Int?, forName name: String?,
        in defaults: UserDefaults = .standard
    ) {
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

    static func tintIndex(for name: String?, in defaults: UserDefaults = .standard) -> Int {
        guard let name, !name.isEmpty, name == defaults.string(forKey: myTintNameKey)
        else { return derivedIndex(for: name) }
        if let picked = defaults.object(forKey: myTintKey) as? Int {
            return paletteUIColors.indices.contains(picked) ? picked : derivedIndex(for: name)
        }
        if let legacy = defaults.object(forKey: legacyTintKey) as? Int,
           legacyTintRemap.indices.contains(legacy) {
            return legacyTintRemap[legacy]
        }
        return derivedIndex(for: name)
    }

    static func derivedIndex(for name: String?) -> Int {
        guard let name, !name.isEmpty else { return 1 }
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % paletteUIColors.count
    }

    static func uiColor(for name: String?) -> UIColor {
        guard let name, !name.isEmpty else { return .oneDayBrand }
        return paletteUIColors[tintIndex(for: name) % paletteUIColors.count]
    }
    static func initial(for name: String?) -> String {
        guard let name, let first = name.first else { return "" }
        return String(first).uppercased()
    }
}
