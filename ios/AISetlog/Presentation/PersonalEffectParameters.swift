import Foundation

/// How you want your own footage graded.
///
/// Three dials, and all three are things a camera got wrong rather than things
/// wrong with your face: it underexposed you, it read the room's light as the
/// wrong colour, it flattened everything out. There is no "beauty" dial, and
/// nothing here softens skin — that word presumes something needs fixing.
///
/// The numbers are UI units, `-50` to `+50`, and `0` is the file as it was
/// recorded. Centre is the default on every dial, so "off" is a place you can
/// get back to by feel rather than by remembering a preset name. What Core
/// Image wants — EV, a white point in kelvin, a contrast multiplier — is derived
/// at the bottom of this file, because that is the part with numbers in it that
/// can be wrong, and it belongs next to the range it converts from.
///
/// Nothing here touches the recorded file. The grade is applied when a clip is
/// played and again when a film is exported, so turning it off gives back
/// exactly what the camera saw.
struct PersonalEffectParameters: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    /// Darker below zero, brighter above.
    var exposure: Double
    /// Cooler below zero, warmer above.
    var temperature: Double
    /// Flatter below zero, punchier above.
    var contrast: Double

    /// Values arrive from a dial, from `@AppStorage`, and from whatever was on
    /// disk two versions ago. Only the first of those is trustworthy.
    init(exposure: Double = 0, temperature: Double = 0, contrast: Double = 0) {
        self.exposure = Self.clamp(exposure)
        self.temperature = Self.clamp(temperature)
        self.contrast = Self.clamp(contrast)
    }

    /// Spelled out rather than synthesized, because this type is also
    /// `RawRepresentable` and the standard library will happily encode any such
    /// type as its bare raw value. A missing key means that dial was centred,
    /// not that the file is broken.
    private enum CodingKeys: String, CodingKey {
        case exposure, temperature, contrast
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            exposure: try box.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
            temperature: try box.decodeIfPresent(Double.self, forKey: .temperature) ?? 0,
            contrast: try box.decodeIfPresent(Double.self, forKey: .contrast) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(exposure, forKey: .exposure)
        try box.encode(temperature, forKey: .temperature)
        try box.encode(contrast, forKey: .contrast)
    }

    static let range: ClosedRange<Double> = -50...50

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// What the camera saw. The default, and what every dial centres on.
    static let none = PersonalEffectParameters()

    /// Whether applying this would change a single pixel.
    ///
    /// The check that matters most in the whole file: when it's true every
    /// caller skips the chain entirely, so "off" costs nothing and, more to the
    /// point, can't be a source of drift.
    var isIdentity: Bool { self == .none }

    // MARK: - What Core Image wants

    /// `CIExposureAdjust` inputEV.
    ///
    /// ±1.5 stops at the ends. Wider would let someone silently blow out a face
    /// they can't recover, and the dial is for rescuing a dim room, not for
    /// relighting one.
    var exposureEV: Double { exposure / 50 * 1.5 }

    /// The white point `CITemperatureAndTint` is asked to move the picture to,
    /// away from `neutralTemperature`.
    ///
    /// 6500K is daylight. ±2000K reaches tungsten at one end and overcast shade
    /// at the other, which is the whole range of light people actually film in.
    /// Note the inversion: a *warmer* picture comes from naming a *lower* target
    /// white point, because the filter is correcting towards it.
    var targetTemperature: Double { Self.neutralTemperature - temperature / 50 * 2000 }

    /// `CIColorControls` inputContrast, where 1 is unchanged.
    var contrastMultiplier: Double { 1 + contrast / 50 * 0.4 }

    /// The white point a picture is assumed to already have, so the chain can
    /// say "from here to there" even when `temperature` is centred.
    static let neutralTemperature = 6500.0
}

// MARK: - Storage

/// One string, so `@AppStorage` can hold it.
///
/// Three separate keys would let a half-written update leave one dial from this
/// session and two from the last one.
extension PersonalEffectParameters: RawRepresentable {
    /// What the views bind to. One key, so playback and export can't disagree
    /// about what you chose.
    ///
    /// `v2` because `v1` held the old smoothing/brightness/warmth presets on a
    /// 0...1 scale. Those aren't migrated and can't honestly be: there is no
    /// skin-smoothing dial any more to carry `smoothing` over to, and silently
    /// reinterpreting the other two as exposure and temperature would change
    /// what someone's clips look like without them asking. An old install opens
    /// on "as shot", which is the one state nobody can be surprised by.
    static let storageKey = "personalEffect.v2"

    /// Whether the grade outlives the app being closed.
    ///
    /// Two keys rather than one because "grade this clip" and "grade everything
    /// from now on" are different requests, and the second one deserves to be
    /// asked for rather than assumed. Off is the default: a dial you moved once,
    /// on a day you didn't like your face, shouldn't quietly become how you see
    /// every day after it.
    static let stickyKey = "personalEffect.sticky.v2"

    /// What the app should open on, given what was stored and whether you asked
    /// it to stick. Pure so the rule is testable — the alternative is finding
    /// out by quitting the app.
    static func onLaunch(
        stored: PersonalEffectParameters, sticky: Bool
    ) -> PersonalEffectParameters {
        sticky ? stored : .none
    }

    var rawValue: String {
        [exposure, temperature, contrast]
            .map { String(format: "%.2f", $0) }
            .joined(separator: ",")
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.map { Double($0) }
        guard numbers.allSatisfy({ $0 != nil }) else { return nil }
        self.init(
            exposure: numbers[0]!, temperature: numbers[1]!, contrast: numbers[2]!)
    }
}
