import Foundation

extension Strings {
    private static func filterCopy(_ zh: String, _ en: String) -> String {
        AppLanguage.effective.resolved == .chinese ? zh : en
    }

    static var filmOrder: String { filterCopy("排顺序", "Order") }
    static var filmFilter: String { filterCopy("筛选", "Pick") }
    static var filmPeopleHeader: String { filterCopy("成片里有谁", "Who's in it") }
    static var filmPerPersonHeader: String { filterCopy("一段一段挑", "Clip by clip") }
    static var filmLeftOut: String { filterCopy("没放进", "Left out") }
    static func filmClipsKept(_ kept: Int, of total: Int) -> String {
        kept == total
            ? filterCopy("\(total) 段", "\(total) clip\(total == 1 ? "" : "s")")
            : filterCopy("\(kept)/\(total) 段", "\(kept) of \(total)")
    }
    static func filmClipsHeld(_ count: Int) -> String {
        filterCopy("\(count) 段定格", "\(count) frozen")
    }
    static var filmNothingLeft: String {
        filterCopy("至少留一段", "Keep at least one")
    }

    static var filmPersonIncluded: String { filterCopy("放进成片", "In the film") }
    static var filmPersonAllHeld: String { filterCopy("每一段都定格", "Freeze every clip") }
    static var filmEachClip: String { filterCopy("每一段", "Each clip") }
    static var filmClipInFilm: String { filterCopy("要这段", "Use this clip") }
    static var filmHold: String { filterCopy("定格", "Freeze") }
    static func filmHeldAt(_ seconds: Double) -> String {
        filterCopy(
            "停在第 \(String(format: "%.1f", seconds)) 秒",
            "Stops at \(String(format: "%.1f", seconds))s")
    }
    static var filmHoldDragHint: String {
        filterCopy("拖动选停在哪一帧", "Drag to pick the frame")
    }
    static func filmClipNumber(_ n: Int) -> String { filterCopy("第 \(n) 段", "Clip \(n)") }
}
