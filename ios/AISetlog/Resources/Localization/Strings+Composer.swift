import Foundation

/// The one-page composer's own copy (1.5). Kept apart from `Localization.swift`
/// so the composer can change without touching the shared table.
extension Strings {
    private static var isChinese: Bool { AppLanguage.effective.resolved == .chinese }

    // MARK: The page

    static var composerWhatToFilm: String { isChinese ? "今天拍什么" : "What to film today" }
    static var composerWriteList: String { isChinese ? "写今天的清单" : "Write today's list" }
    static var composerWriteListLead: String {
        isChinese ? "自己写，或者让 AI 帮你写" : "Type it, or let AI draft it"
    }
    static var composerByTimeTitle: String { isChinese ? "不写，按时间拍" : "No list, by time" }
    static var composerByTimeLead: String {
        isChinese ? "看到什么拍什么，自动记下时间" : "Film what happens, timed for you"
    }
    static var composerHowManyDays: String { isChinese ? "拍几天" : "How many days" }
    static var composerPlanOneDay: String { isChinese ? "一日计划" : "One-day plan" }
    static var composerPlanOneDayLead: String {
        isChinese ? "今天拍完，当天剪成一支片" : "Film it today, one film tonight"
    }
    static var composerPlanSevenDay: String { isChinese ? "7 日计划" : "7-day plan" }
    static var composerPlanSevenDayLead: String {
        isChinese ? "每天拍一段，七天连成一支片" : "One a day, seven days, one film"
    }
    static var composerTemplates: String { isChinese ? "模板" : "Templates" }
    /// 从模板开始's line before anything is picked: how many there are to see.
    static func composerTemplateEntryLead(_ count: Int) -> String {
        isChinese ? "\(count) 个现成的清单，挑一个改改" : "\(count) ready-made lists to start from"
    }
    /// 从模板开始's line once one is picked, so the page says what it is
    /// without the grid that used to show it.
    static func composerTemplateChosen(_ name: String) -> String {
        isChinese ? "已选：\(name)" : "Chosen: \(name)"
    }
    static var composerMineBadge: String { isChinese ? "我的" : "Mine" }
    static var composerName: String { isChinese ? "名字" : "Name" }
    static func composerListSummary(_ count: Int) -> String {
        isChinese ? "清单 · \(count) 项" : "List · \(count) items"
    }
    static var composerListEmpty: String { isChinese ? "清单 · 还没写" : "List · not written yet" }
    static var composerFilmSolo: String { isChinese ? "自己拍" : "Just me" }
    static var composerFilmTogether: String { isChinese ? "和朋友一起拍" : "With friends" }

    // MARK: 写今天的清单

    static var listIntentPlaceholder: String { isChinese ? "今天想做什么？" : "What's today for?" }
    static var listHelpWrite: String { isChinese ? "帮我写" : "Draft it" }
    static var listHelpAgain: String { isChinese ? "换一批" : "Another" }
    static var listHelpWorking: String { isChinese ? "写着呢…" : "Drafting…" }
    static var listSection: String { isChinese ? "清单" : "List" }
    static var listAddRow: String { isChinese ? "加一项" : "Add item" }
    static var listFromIdeas: String { isChinese ? "从提示库选" : "From ideas" }
    static var listSaveAsTemplate: String { isChinese ? "存为我的模板" : "Save as my template" }
    static var listSaveAsTemplateNote: String {
        isChinese ? "开始拍时用选题名字存，下次在「模板」里直接选。"
            : "Saved under the story's name when you start, ready in Templates next time."
    }
    static func listUseCount(_ count: Int) -> String {
        isChinese ? "用这 \(count) 项" : "Use these \(count)"
    }
    static var listUse: String { isChinese ? "至少写两项" : "Write at least two" }

    /// 按时间拍's default name: the day it's filmed, 「10月17日」 / 「Oct 17」.
    static func byTimeTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().locale(AppLanguage.effective.locale))
    }
    static var listFromTemplate: String { isChinese ? "从模板开始" : "Start from a template" }
}
