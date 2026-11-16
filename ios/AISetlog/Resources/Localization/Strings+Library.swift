import Foundation

extension Strings {
    private static var isChinese: Bool { AppLanguage.effective.resolved == .chinese }


    static var filmNextMoment: String { isChinese ? "拍下一段" : "Film the next one" }
}
