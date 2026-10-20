import Foundation

/// Copy for the 我的 archive's camera filter and the story page's diary
/// timeline. Kept out of `Localization.swift` so parallel edits don't collide.
extension Strings {
    private static var isChinese: Bool { AppLanguage.effective.resolved == .chinese }


    /// The diary timeline's main button once at least one moment is filmed.
    static var filmNextMoment: String { isChinese ? "拍下一段" : "Film the next one" }
}
