import Foundation

/// Camera strings added with tap-to-film and the movable dual-camera inset.
/// Kept out of `Localization.swift` so this feature's copy lives in one place.
extension Strings {
    /// VoiceOver's hint on the idle shutter. Not drawn any more (1.5); every
    /// take is the same two seconds, so it says what a tap does and how long.
    static var tapToFilmTwoSeconds: String {
        AppLanguage.effective.resolved == .chinese ? "点一下，拍 2 秒" : "Tap to film 2s"
    }
}
