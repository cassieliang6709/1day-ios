import Foundation

extension Strings {
    private static var zh: Bool { AppLanguage.effective.resolved == .chinese }

    static var libraryDraftQuestion: String { zh ? "这段只有你看得到" : "Only you can see this clip" }
    static var libraryFileIntoStory: String { zh ? "发到房间" : "Send to a room" }
    static var libraryOpenStory: String { zh ? "打开选题" : "Open topic" }
    static var libraryAddCaption: String { zh ? "加字幕" : "Add caption" }
    static var libraryEditCaption: String { zh ? "改字幕" : "Edit caption" }
    static var libraryCaptionPlaceholder: String { zh ? "这一段想说什么" : "Say something about this clip" }
    static var libraryCaptionSave: String { zh ? "好了" : "Done" }

    static func librarySelectedSummary(_ count: Int, seconds: Int?) -> String {
        let clips = zh ? "\(count) 段" : (count == 1 ? "1 clip" : "\(count) clips")
        guard let seconds, count > 0 else { return clips }
        return zh ? "\(clips) · \(seconds) 秒" : "\(clips) · about \(seconds)s"
    }
    static var libraryMakeVlogCTA: String { zh ? "生成 vlog" : "Make vlog" }

    static var vlogArrangeTitle: String { zh ? "排顺序" : "Order" }

    static var todayKeepFilming: String { zh ? "继续拍" : "Film" }
    static var todayWatch: String { zh ? "看成片" : "Watch" }

    static var draftNoPlace: String { zh ? "还没有房间" : "No rooms yet" }
    static var draftNoStoryYet: String {
        zh ? "这段还没有能放进去的选题。在「\(surfacePlans)」页点「＋ \(surfaceCompose)」建一个，就能放进去了。"
            : "There's no story this clip can go into yet. Tap + \(surfaceCompose) on \(surfacePlans) to make one, and it can go in."
    }
    static var draftEveryStoryFull: String {
        zh ? "能放这段的选题都拍满了，再放会盖掉已有的片段。新建一个选题，或者在已有的选题里删掉一段，就有位置了。"
            : "Every story this clip could go into is full, and filing would overwrite a clip. Make a new story, or clear a moment in one, and it has somewhere to go."
    }
}
