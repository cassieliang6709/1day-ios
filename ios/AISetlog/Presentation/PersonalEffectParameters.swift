import Foundation

struct PersonalEffectParameters: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var exposure: Double
    var temperature: Double
    var contrast: Double

    init(exposure: Double = 0, temperature: Double = 0, contrast: Double = 0) {
        self.exposure = Self.clamp(exposure)
        self.temperature = Self.clamp(temperature)
        self.contrast = Self.clamp(contrast)
    }

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

    static let none = PersonalEffectParameters()

    var isIdentity: Bool { self == .none }


    var exposureEV: Double { exposure / 50 * 1.5 }

    var targetTemperature: Double { Self.neutralTemperature - temperature / 50 * 2000 }

    var contrastMultiplier: Double { 1 + contrast / 50 * 0.4 }

    static let neutralTemperature = 6500.0
}
