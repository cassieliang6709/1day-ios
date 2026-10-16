import Foundation

/// The one-page composer's own copy (1.5). Kept apart from `Localization.swift`
/// so the composer can change without touching the shared table.
extension Strings {
    private static var isChinese: Bool { AppLanguage.effective.resolved == .chinese }

    static var composerWhatToFilm: String { isChinese ? "今天拍什么" : "What to film today" }
    static var composerByTimeTitle: String { isChinese ? "不写，\n按时间拍" : "No list, by time" }
    static var composerByTimeLead: String { isChinese ? "看到什么拍什么" : "Film what happens" }
    static var composerHowManyDays: String { isChinese ? "拍几天" : "How many days" }
    static var composerPlanOneDay: String { isChinese ? "制定你的一日计划" : "Plan your day" }
    static var composerPlanOneDayLead: String {
        isChinese ? "今天拍完，当天剪成一支片" : "Film it today, one film tonight"
    }
    static var composerPlanSevenDay: String { isChinese ? "制定你的 7 日计划" : "Plan your 7 days" }
    static var composerPlanSevenDayLead: String {
        isChinese ? "每天拍一段，七天连成一支片" : "One a day, seven days, one film"
    }
    static var composerOptionalTemplates: String {
        isChinese ? "可以套个模板，不选也行" : "Pick a template if you like"
    }
    static var composerMadeBefore: String { isChinese ? "之前做过的" : "Made before" }
    static var composerThisStory: String { isChinese ? "这个故事" : "This story" }
    static var composerWriteListFirst: String {
        isChinese ? "先写下要拍的几件事" : "Write what you'll film first"
    }
    static var composerEditList: String { isChinese ? "改一改" : "Edit" }
}
