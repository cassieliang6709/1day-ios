import Foundation

/// Copy for 我的's 待归档 chip, the vlog selection bar and arrange sheet, and
/// the today rows. Its own file so parallel edits don't collide.
extension Strings {
    private static var zh: Bool { AppLanguage.effective.resolved == .chinese }

    /// A clip in no story or room is no longer "waiting to be filed": it is
    /// kept in 我的, seen only by you, and can be sent on from there.
    static func libraryDraftsChip(_ n: Int) -> String { zh ? "只有我 (\(n))" : "Only me (\(n))" }
    /// The chip that brings friends' clips into 我的; off by default.
    static var libraryIncludeFriendsChip: String { zh ? "含朋友的" : "Incl. friends" }
    /// The corner badge on a draft's tile.
    static var libraryDraftBadge: String { zh ? "只有我" : "Only me" }
    static var libraryDraftQuestion: String { zh ? "这段只有你看得到" : "Only you can see this clip" }
    static var libraryFileIntoStory: String { zh ? "放进选题或发到房间" : "Add to a topic or room" }
    static var libraryOpenStory: String { zh ? "打开选题" : "Open topic" }
    static var libraryAddCaption: String { zh ? "加字幕" : "Add caption" }
    static var libraryEditCaption: String { zh ? "改字幕" : "Edit caption" }
    static var libraryCaptionPlaceholder: String { zh ? "这一段想说什么" : "Say something about this clip" }
    static var libraryCaptionSave: String { zh ? "好了" : "Done" }

    /// "已选 4 段 · 约 8 秒". Seconds are nil until the files have been read.
    static func librarySelectedSummary(_ count: Int, seconds: Int?) -> String {
        let clips = zh ? "已选 \(count) 段" : (count == 1 ? "1 clip" : "\(count) clips")
        guard let seconds, count > 0 else { return clips }
        return zh ? "\(clips) · 约 \(seconds) 秒" : "\(clips) · about \(seconds)s"
    }
    static var libraryMakeVlogCTA: String { zh ? "生成 vlog" : "Make vlog" }

    static var vlogArrangeTitle: String { zh ? "排一下顺序" : "Arrange clips" }
    static var vlogArrangeHint: String {
        zh ? "按住右边的横线拖动换顺序，点一段看看。" : "Drag the handle to reorder. Tap a clip to preview it."
    }

    /// The today row's button.
    static var todayKeepFilming: String { zh ? "继续拍" : "Film" }
    static var todayWatch: String { zh ? "看成片" : "Watch" }

    // Filing a draft, without 竖屏/横屏/正方形: cameras decide the shape now.
    // The matching underneath still checks the frame (old stories need it).
    static var draftNoPlace: String { zh ? "还没有选题能放这段" : "No story can take this clip yet" }
    static var draftNoStoryYet: String {
        zh ? "这段还没有能放进去的选题。在「\(surfacePlans)」页点「＋ \(surfaceCompose)」建一个，就能放进去了。"
            : "There's no story this clip can go into yet. Tap + \(surfaceCompose) on \(surfacePlans) to make one, and it can go in."
    }
    static var draftEveryStoryFull: String {
        zh ? "能放这段的选题都拍满了，再放会盖掉已有的片段。新建一个选题，或者在已有的选题里删掉一段，就有位置了。"
            : "Every story this clip could go into is full, and filing would overwrite a clip. Make a new story, or clear a moment in one, and it has somewhere to go."
    }
}
