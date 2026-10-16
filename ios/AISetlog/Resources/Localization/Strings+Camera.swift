import Foundation

/// Camera strings added with tap-to-film and the movable dual-camera inset.
/// Kept out of `Localization.swift` so this feature's copy lives in one place.
extension Strings {
    /// Under the idle shutter. Every take is the same two seconds now, so the
    /// line says both what to do and how long it lasts.
    static var tapToFilmTwoSeconds: String {
        AppLanguage.effective.resolved == .chinese ? "点一下，拍 2 秒" : "Tap to film 2s"
    }
    /// Under the countdown ring. The take stops on its own; there is nothing
    /// to press, so the line no longer offers a stop.
    static var filmingTwoSeconds: String {
        AppLanguage.effective.resolved == .chinese ? "正在拍，2 秒自动停" : "Filming, stops at 2s"
    }
}
