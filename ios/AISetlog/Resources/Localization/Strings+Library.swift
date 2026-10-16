import Foundation

/// Copy for the 我的 archive's camera filter and the story page's diary
/// timeline. Kept out of `Localization.swift` so parallel edits don't collide.
extension Strings {
    private static var isChinese: Bool { AppLanguage.effective.resolved == .chinese }

    /// The people menu's "no restriction" option.
    static var filterEveryone: String { isChinese ? "全部人" : "Everyone" }
    /// Accessibility label for the people menu.
    static var filterWhoFilmed: String { isChinese ? "谁拍的" : "Who filmed it" }

    /// The diary timeline's main button once at least one moment is filmed.
    static var filmNextMoment: String { isChinese ? "拍下一段" : "Film the next one" }
}
