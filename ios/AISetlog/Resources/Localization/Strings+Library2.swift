import Foundation

/// Copy for 我的's 待归档 chip, the vlog selection bar and arrange sheet, and
/// the today rows. Its own file so parallel edits don't collide.
extension Strings {
    private static var zh: Bool { AppLanguage.effective.resolved == .chinese }

    /// A clip in no story or room is no longer "waiting to be filed": it is
    /// kept in 我的, seen only by you, and can be sent on from there.
    static func libraryDraftsChip(_ n: Int) -> String { zh ? "只有我 (\(n))" : "Only me (\(n))" }
    /// The corner badge on a draft's tile.
    static var libraryDraftBadge: String { zh ? "只有我" : "Only me" }
    static var libraryDraftQuestion: String { zh ? "这段只有你看得到" : "Only you can see this clip" }
    static var libraryFileIntoStory: String { zh ? "发到房间或故事" : "Send to a room or story" }
    static var libraryOpenStory: String { zh ? "打开故事" : "Open story" }

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
    static var draftNoPlace: String { zh ? "还没有故事能放这段" : "No story can take this clip yet" }
    static var draftNoStoryYet: String {
        zh ? "这段还没有能放进去的故事。在「\(surfacePlans)」页点「＋ \(surfaceCompose)」建一个，就能放进去了。"
            : "There's no story this clip can go into yet. Tap + \(surfaceCompose) on \(surfacePlans) to make one, and it can go in."
    }
    static var draftEveryStoryFull: String {
        zh ? "能放这段的故事都拍满了，再放会盖掉已有的片段。新建一个故事，或者在已有的故事里删掉一段，就有位置了。"
            : "Every story this clip could go into is full, and filing would overwrite a clip. Make a new story, or clear a moment in one, and it has somewhere to go."
    }
}
