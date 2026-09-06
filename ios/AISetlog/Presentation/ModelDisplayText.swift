import Foundation

extension Challenge.ClipLength {
    var secondsLabel: String {
        Strings.seconds(Int(seconds))
    }
}

extension ChallengeTemplate {
    /// Emotional line, falling back to a generic one for user-built scripts.
    var displayBlurb: String {
        blurb?.resolved()
            ?? Self.legacyCompatibility(matching: name.en)?.blurb?.resolved()
            ?? Strings.customTemplateBlurb
    }
}
