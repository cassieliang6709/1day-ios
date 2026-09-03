import Foundation

/// How soft you want to look.
///
/// Three dials, not a slider called "beauty": that word presumes something is
/// wrong with your face and this is the fix. These are the three things people
/// actually reach for when a phone camera has been unkind — take the edge off
/// the skin, lift it out of the gloom, warm it up.
///
/// The values are what you set. What a filter chain needs — a blur radius in
/// pixels, a saturation multiplier, a colour temperature in kelvin — is derived
/// from them, and that derivation lives here rather than next to the
/// `CIFilter`s, because it's the part with numbers in it that can be wrong.
///
/// Nothing here touches the recorded file. The look is applied when a clip is
/// played and again when a film is exported, so turning it off gives you back
/// exactly what the camera saw. That's the whole reason this is a value and not
/// a step in the capture pipeline.
struct GentleLook: Equatable, Codable, Sendable {
    /// Softens skin. 0 is the camera's own sharpness.
    let smoothing: Double
    /// Lifts the picture out of the gloom, and lets a little colour go with it.
    let brightness: Double
    /// Pulls the white point towards afternoon light.
    let warmth: Double

    /// Values arrive from a slider, from `@AppStorage`, and from whatever was
    /// on disk two versions ago. Only the first of those is trustworthy.
    init(smoothing: Double = 0, brightness: Double = 0, warmth: Double = 0) {
        self.smoothing = Self.clamp(smoothing)
        self.brightness = Self.clamp(brightness)
        self.warmth = Self.clamp(warmth)
    }

    /// Spelled out rather than synthesized, because this type is also
    /// `RawRepresentable` and the standard library will happily encode any such
    /// type as its bare raw value. Three named keys is what a stored film
    /// should have next to it — and a missing key means that dial was off,
    /// not that the file is broken.
    private enum CodingKeys: String, CodingKey {
        case smoothing, brightness, warmth
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            smoothing: try box.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0,
            brightness: try box.decodeIfPresent(Double.self, forKey: .brightness) ?? 0,
            warmth: try box.decodeIfPresent(Double.self, forKey: .warmth) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(smoothing, forKey: .smoothing)
        try box.encode(brightness, forKey: .brightness)
        try box.encode(warmth, forKey: .warmth)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// Whether applying this would change a single pixel.
    ///
    /// The check that matters most in the whole file: when it's true every
    /// caller skips the chain entirely, so "off" costs nothing and, more to the
    /// point, can't be a source of drift.
    var isIdentity: Bool { self == .none }

    // MARK: - Presets

    /// What the camera saw. The default, and the first one in the picker.
    static let none = GentleLook()
    /// Barely there — the one for "I look tired", not "I look bad".
    static let clean = GentleLook(smoothing: 0.35, brightness: 0.30, warmth: 0.15)
    /// The obvious one. Still short of plastic.
    static let soft = GentleLook(smoothing: 0.60, brightness: 0.50, warmth: 0.35)
    /// Late afternoon, indoors, in January.
    static let warm = GentleLook(smoothing: 0.45, brightness: 0.35, warmth: 0.80)

    /// In picker order, each with a key the UI can localize.
    static let presets: [(key: String, look: GentleLook)] = [
        ("look_none", .none), ("look_clean", .clean),
        ("look_soft", .soft), ("look_warm", .warm),
    ]

    /// Which preset this is, if it's still one of them. Nil once you've moved
    /// a slider — the picker then has nothing highlighted, which is honest.
    var presetKey: String? {
        Self.presets.first { $0.look == self }?.key
    }

    // MARK: - What a filter chain needs

    /// The derived numbers, in the units Core Image wants.
    struct Parameters: Equatable {
        /// Gaussian sigma for the softening pass, in pixels.
        let blurRadius: Double
        /// How much of the blurred copy is mixed straight back in, 0...1. This
        /// is the one that actually takes texture off skin.
        let blurOpacity: Double
        /// How much of the soft-light pass is mixed in on top, 0...1. This one
        /// adds the glow without touching the edges.
        let softLightOpacity: Double
        /// Added to every channel by `CIColorControls`.
        let brightnessDelta: Double
        /// `CIColorControls` saturation multiplier.
        let saturation: Double
        /// Target white point for `CITemperatureAndTint`, (kelvin, tint).
        let temperature: Double
        let tint: Double
    }

    /// Ceilings, all four chosen to stop short of looking retouched.
    ///
    /// Brightness is the one to be careful with: `CIColorControls` brightness
    /// is an additive offset, so 0.06 is already a visible lift and 0.2 would
    /// wash the picture out completely. Saturation comes *down* as brightness
    /// goes up, because lifting a face without it makes the skin go orange.
    private enum Ceiling {
        static let blurRadius = 8.0
        /// Deliberately the smaller of the two. Blur mixed in is what makes a
        /// face look plastic when it's overdone; the glow on top is what makes
        /// it look kind. So most of the effect comes from the glow.
        static let blurOpacity = 0.35
        static let softLightOpacity = 0.55
        static let brightnessDelta = 0.06
        static let saturationDrop = 0.08
        /// Neutral daylight, and the afternoon we're heading for.
        static let neutralTemperature = 6500.0
        static let warmTemperature = 5200.0
        static let tint = 8.0
    }

    var parameters: Parameters {
        Parameters(
            blurRadius: smoothing * Ceiling.blurRadius,
            blurOpacity: smoothing * Ceiling.blurOpacity,
            softLightOpacity: smoothing * Ceiling.softLightOpacity,
            brightnessDelta: brightness * Ceiling.brightnessDelta,
            saturation: 1 - brightness * Ceiling.saturationDrop,
            temperature: Ceiling.neutralTemperature
                + warmth * (Ceiling.warmTemperature - Ceiling.neutralTemperature),
            tint: warmth * Ceiling.tint)
    }

    /// The white point a picture already has, so a chain can say "from here to
    /// there" even when `warmth` is 0.
    static var neutralTemperature: Double { Ceiling.neutralTemperature }
}

// MARK: - Storage

/// One string, so `@AppStorage` can hold it.
///
/// Three separate keys would let a half-written update leave you with one
/// dial's worth of somebody else's preset.
extension GentleLook: RawRepresentable {
    /// What the views bind to. One key, so playback and export can't disagree
    /// about what you chose.
    static let storageKey = "gentleLook.v1"

    var rawValue: String {
        [smoothing, brightness, warmth]
            .map { String(format: "%.4f", $0) }
            .joined(separator: ",")
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.map { Double($0) }
        guard numbers.allSatisfy({ $0 != nil }) else { return nil }
        self.init(
            smoothing: numbers[0]!, brightness: numbers[1]!, warmth: numbers[2]!)
    }
}
