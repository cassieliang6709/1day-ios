import Foundation
import SwiftUI


enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }

    static let storageKey = "appAppearance"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: Strings.systemAppearance
        case .light: Strings.lightAppearance
        case .dark: Strings.darkAppearance
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system, english, chinese

    var id: String { rawValue }

    static let storageKey = "appLanguage"

    var localeCode: String {
        switch self {
        case .system: Locale.current.language.languageCode?.identifier ?? "en"
        case .english: "en"
        case .chinese: "zh-Hans"
        }
    }

    var displayName: String {
        switch self {
        case .system: Strings.systemLanguage
        case .english: "English"
        case .chinese: "中文"
        }
    }

    func resolved(locale: Locale = .current) -> AppLanguage {
        guard self == .system else { return self }
        return locale.language.languageCode?.identifier == "zh" ? .chinese : .english
    }

    var resolved: AppLanguage { resolved() }

    var locale: Locale { Locale(identifier: resolved.localeCode) }

    static var effective: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        return stored.resolved()
    }
}


struct LocalizedText: Codable, Equatable, Hashable {
    var translations: [String: String]

    init(en: String, zh: String) {
        translations = ["en": en, "zh-Hans": zh]
    }

    init(translations: [String: String]) {
        self.translations = translations
    }

    var en: String { translations["en"] ?? translations.values.first ?? "" }
    var zh: String { translations["zh-Hans"] ?? en }

    func resolved(_ lang: AppLanguage = .effective) -> String {
        translations[lang.resolved.localeCode]
            ?? translations["en"]
            ?? translations.values.first
            ?? ""
    }

    private enum CodingKeys: String, CodingKey { case translations, en, zh }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let dict = try? c.decode([String: String].self, forKey: .translations) {
            translations = dict
        } else {
            let en = (try? c.decode(String.self, forKey: .en)) ?? ""
            let zh = (try? c.decode(String.self, forKey: .zh)) ?? en
            translations = ["en": en, "zh-Hans": zh]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(translations, forKey: .translations)
    }
}


enum Strings {
    private static var lang: AppLanguage { AppLanguage.effective.resolved }


    static var ok: String { lang == .chinese ? "好" : "OK" }
    static var cancel: String { lang == .chinese ? "取消" : "Cancel" }
    static var done: String { lang == .chinese ? "完成" : "Done" }
    static var save: String { lang == .chinese ? "保存" : "Save" }
    static var apply: String { lang == .chinese ? "应用" : "Apply" }
    static var delete: String { lang == .chinese ? "删除" : "Delete" }
    static var paste: String { lang == .chinese ? "粘贴" : "Paste" }
    static var settings: String { lang == .chinese ? "设置" : "Settings" }
    static var language: String { lang == .chinese ? "语言" : "Language" }
    static var systemLanguage: String { lang == .chinese ? "跟随系统" : "System" }

    static var play: String { lang == .chinese ? "播放" : "Play" }
    static var pause: String { lang == .chinese ? "暂停" : "Pause" }
    static var fullScreen: String { lang == .chinese ? "全屏" : "Full screen" }
    static var playbackPosition: String { lang == .chinese ? "播放进度" : "Playback position" }
    static var close: String { lang == .chinese ? "关闭" : "Close" }

    static var notifications: String { lang == .chinese ? "通知" : "Notifications" }
    static var eveningReminder: String {
        lang == .chinese ? "晚间拍摄提醒" : "Evening capture reminder"
    }
    static var reminderTime: String { lang == .chinese ? "提醒时间" : "Reminder time" }
    static var friendActivity: String { lang == .chinese ? "好友动态" : "Friend activity" }
    static var showFriendNames: String {
        lang == .chinese ? "在通知中显示好友名字" : "Show friend names in notifications"
    }
    static var sharedRooms: String { lang == .chinese ? "共享挑战" : "Shared challenges" }
    static var allRoomsOn: String { lang == .chinese ? "都开着" : "All on" }
    static func roomsMuted(_ count: Int) -> String {
        lang == .chinese ? "静音了 \(count) 个" : "\(count) muted"
    }
    static var notificationPermissionDenied: String {
        lang == .chinese
            ? "系统通知已关闭。请到 iPhone 设置中允许 1Day 通知。"
            : "Notifications are off in iPhone Settings. Allow notifications for 1Day to use this."
    }
    static var openSettings: String { lang == .chinese ? "打开系统设置" : "Open Settings" }
    static var notificationPrimerTitle: String {
        lang == .chinese ? "留住今天的瞬间？" : "Keep today’s moment?"
    }
    static var notificationPrimerFootnote: String {
        lang == .chinese
            ? "你可以随时在“设置”中关闭或改时间。"
            : "You can turn this off or change the time in Settings anytime."
    }
    static var enableEveningReminder: String {
        lang == .chinese ? "开启晚间提醒" : "Enable evening reminder"
    }
    static var recordNow: String { lang == .chinese ? "现在拍摄" : "Record now" }
    static var remindInOneHour: String {
        lang == .chinese ? "1 小时后提醒" : "Remind me in 1 hour"
    }
    static func eveningOneDayReminder(remaining: Int) -> String {
        lang == .chinese
            ? "今天还差 \(remaining) 个瞬间，留一个给此刻吧。"
            : "\(remaining) moment\(remaining == 1 ? "" : "s") left today. Save one for now."
    }
    private static func named(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    static func roomClipActivity(name: String?) -> String {
        if lang == .chinese {
            return named(name).map { "\($0) 刚拍了一段" } ?? "有人刚拍了一段"
        }
        return named(name).map { "\($0) just filmed a clip" } ?? "Someone just filmed a clip"
    }
    static func roomCommentActivity(name: String?) -> String {
        if lang == .chinese {
            return named(name).map { "\($0) 评论了你们的片段。" } ?? "有人评论了你们的片段。"
        }
        return named(name).map { "\($0) commented on your shared film." }
            ?? "Someone commented on your shared film."
    }
    static func roomPokeActivity(name: String?) -> String {
        if lang == .chinese {
            return named(name).map { "\($0) 拍了拍你" } ?? "有人拍了拍你"
        }
        return named(name).map { "\($0) poked you — come film something" }
            ?? "Someone poked you — come film something"
    }

    static func roomReactionActivity(name: String?) -> String {
        if lang == .chinese {
            return named(name).map { "\($0) 回应了" } ?? "有人回应了"
        }
        return named(name).map { "\($0) reacted to your shared film." }
            ?? "Someone reacted to your shared film."
    }

    static func roomClipAlertFormat(named: Bool) -> String {
        if lang == .chinese { return named ? "%1$@ 刚拍了一段" : "有人刚拍了一段" }
        return named ? "%1$@ just filmed a clip" : "Someone just filmed a clip"
    }
    static func roomPokeAlertFormat(named: Bool) -> String {
        if lang == .chinese { return named ? "%1$@ 拍了拍你" : "有人拍了拍你" }
        return named ? "%1$@ poked you — come film something" : "Someone poked you — come film something"
    }
    static func roomMessageAlertFormat(named: Bool) -> String {
        if lang == .chinese { return named ? "%1$@：%2$@" : "%1$@" }
        return named ? "%1$@: %2$@" : "%1$@"
    }
    static func roomReactionAlertFormat(named: Bool) -> String {
        if lang == .chinese { return named ? "%1$@ 回应了你们的片段。" : "有人回应了你们的片段。" }
        return named ? "%1$@ reacted to your shared film." : "Someone reacted to your shared film."
    }


    static func dayN(_ day: Int) -> String {
        lang == .chinese ? "第 \(day) 天" : "Day \(day)"
    }
    static func seconds(_ value: Int) -> String {
        lang == .chinese ? "\(value) 秒" : "\(value)s"
    }

    static func unitName(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "个瞬间" : "天" }
        return oneDay ? "moment" : "day"
    }

    static func unitNamePlural(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "个瞬间" : "天" }
        return oneDay ? "moments" : "days"
    }

    static func momentWord(_ count: Int) -> String {
        lang == .chinese ? "个瞬间" : (count == 1 ? "moment" : "moments")
    }

    static func storyLabel(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "一日影片" : "七日挑战" }
        return oneDay ? "1-day film" : "7-day challenge"
    }



    static var startToday: String { lang == .chinese ? "开始今天" : "Start today" }
    static var enterInviteCode: String { lang == .chinese ? "输入邀请码" : "Enter invite code" }
    static var newStory: String { lang == .chinese ? "新建选题" : "New topic" }
    static var couldntJoin: String { lang == .chinese ? "无法加入" : "Couldn't join" }
    static var leaveRoom: String { lang == .chinese ? "退出房间" : "Leave room" }
    static var deleteChallenge: String { lang == .chinese ? "删除选题" : "Delete topic" }

    static func deleteStoryTitle(_ name: String) -> String {
        lang == .chinese ? "删除《\(name)》？" : "Delete “\(name)”?"
    }
    static func deleteStoryWarning(_ clipCount: Int) -> String {
        if lang == .chinese {
            return clipCount > 0
                ? "已经拍的 \(clipCount) 段视频会一起删掉，找不回来。"
                : "这个选题会从这台设备上删掉，找不回来。"
        }
        return clipCount > 0
            ? "The \(clipCount) clip\(clipCount == 1 ? "" : "s") you filmed will be deleted too. This can't be undone."
            : "This story will be deleted from this device. This can't be undone."
    }
    static func leaveRoomTitle(_ name: String) -> String {
        lang == .chinese ? "退出《\(name)》？" : "Leave “\(name)”?"
    }
    static var leaveRoomWarning: String {
        lang == .chinese
            ? "你拍的片段会从房间里删掉，找不回来"
            : "Your clips will be deleted from the room for good"
    }
    static var history: String { lang == .chinese ? "历史" : "HISTORY" }
    static var joining: String { lang == .chinese ? "加入中…" : "Joining…" }
    static var joinTimedOut: String {
        lang == .chinese ? "一直没连上，再试一次？" : "Still no answer — try again?"
    }
    static var creatingRoom: String { lang == .chinese ? "正在建房间…" : "Creating the room…" }
    static var couldNotCreateRoom: String {
        lang == .chinese ? "房间没建起来" : "Couldn't create the room"
    }
    static var joinShort: String { lang == .chinese ? "加入" : "Join" }
    static var haveInviteCode: String { lang == .chinese ? "我有邀请码" : "I have an invite code" }
    static var firstRunHeadline: String {
        lang == .chinese ? "日日是好日" : "Every day is a good day"
    }
    static var firstRunGuide: String {
        lang == .chinese
            ? "按住拍几段，自动拼成一支片"
            : "Hold to film a few clips. They become one film."
    }
    static var firstRunStart: String {
        lang == .chinese ? "开始" : "Start"
    }
    static var firstRunStartHint: String {
        lang == .chinese ? "创建一支包含三个瞬间的个人短片。" : "Creates a personal film with three moments."
    }
    static var firstRunTakeYou: String { lang == .chinese ? "你" : "You" }
    static var firstRunAnimationAccessibility: String {
        lang == .chinese
            ? "你和两个朋友各拍一段，拼成同一个画面一起播放"
            : "You and two friends each film a take, and they play together in one frame"
    }
    static var firstRunSoloFirst: String {
        lang == .chinese ? "先自己拍拍看" : "Try it on my own first"
    }
    static var signInFailed: String {
        lang == .chinese ? "没登上，再试一次" : "Couldn't sign in. Try again."
    }
    static var firstRunJoin: String {
        lang == .chinese ? "有邀请码？加入朋友" : "Have an invite? Join friends"
    }
    static var quickStartTitle: String { lang == .chinese ? "我的一天" : "My day" }
    static var inviteHint: String {
        lang == .chinese ? "向朋友要 6 位邀请码。" : "Ask your friend for the 6-character code."
    }
    static var inviteCodeFormatHint: String {
        lang == .chinese
            ? "可以直接粘贴整段邀请文字。"
            : "Paste the whole invite if you have it."
    }
    static var joinRoomButton: String { lang == .chinese ? "加入房间" : "Join room" }

    static func oneDayProgress(
        _ recorded: Int,
        total: Int,
        secondsLabel: String
    ) -> String {
        lang == .chinese
            ? "\(recorded)/\(total) 个瞬间 · 每段最长 \(secondsLabel) · 24 小时影片"
            : "\(recorded)/\(total) \(secondsLabel) \(momentWord(total)) · 24-hour film"
    }


    static func titlePrompt(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "我的选题…" : "我的七日目标…" }
        return oneDay ? "My 1-day story..." : "My 7-day goal..."
    }
    static var modeOneDay: String { lang == .chinese ? "一日" : "1-Day" }
    static var modeSevenDay: String { lang == .chinese ? "七日" : "7-Day" }
    static var clipLengthHeader: String { lang == .chinese ? "片段时长" : "CLIP LENGTH" }
    static var withFriends: String { lang == .chinese ? "和朋友一起" : "With friends" }
    static var createRoom: String { lang == .chinese ? "创建房间" : "Create room" }
    static func promptN(_ number: Int) -> String {
        lang == .chinese ? "第 \(number) 个拍摄标题" : "Capture title \(number)"
    }


    static var friend: String { lang == .chinese ? "朋友" : "Friend" }
    static func shareMessageCaptured(first: String, title: String, code: String) -> String {
        lang == .chinese
            ? "来 1Day 和我一起拍「\(title)」。邀请码 \(code)\noneday://join?code=\(code)"
            : "Film “\(title)” with me on 1Day. Code \(code)\noneday://join?code=\(code)"
    }
    static func shareMessageInvite(title: String, code: String) -> String {
        lang == .chinese
            ? "来 1Day 和我一起拍「\(title)」。邀请码 \(code)\noneday://join?code=\(code)"
            : "Film “\(title)” with me on 1Day. Code \(code)\noneday://join?code=\(code)"
    }
    static func recordedProgress(
        _ recorded: Int,
        total: Int,
        secondsLabel: String,
        unitPlural: String
    ) -> String {
        lang == .chinese
            ? "\(total) \(unitPlural)中已录 \(recorded) 段（每段最长 \(secondsLabel)）"
            : "\(recorded) of \(total) \(unitPlural) recorded · up to \(secondsLabel) each"
    }
    static func momentCount(_ total: Int) -> String {
        lang == .chinese ? "24 小时，\(total) 个瞬间" : "\(total) \(momentWord(total)) in 24 hours"
    }
    static var record: String { lang == .chinese ? "拍摄" : "Record" }
    static func lockedSlot(oneDay: Bool, day: Int) -> String {
        if lang == .chinese { return oneDay ? "第 \(day) 个瞬间" : "第 \(day) 天" }
        return oneDay ? "Moment \(day)" : "Day \(day)"
    }


    static var retake: String { lang == .chinese ? "重拍" : "Retake" }
    static var useClip: String { lang == .chinese ? "使用这段" : "Use clip" }
    static var unusedClipQuestion: String {
        lang == .chinese ? "这段还没用上" : "You haven't used this clip yet"
    }
    static var recordingFailed: String {
        lang == .chinese ? "没拍成" : "Didn't record"
    }
    static var noSoundOpenSettings: String {
        lang == .chinese ? "没有声音 · 去设置" : "No sound · Settings"
    }
    static var closeCamera: String { lang == .chinese ? "关闭相机" : "Close camera" }
    static var surfacePlans: String { lang == .chinese ? "我的" : "Mine" }
    static var surfaceFriends: String { lang == .chinese ? "房间" : "Rooms" }
    static var surfaceCompose: String { lang == .chinese ? "新建" : "New" }
    static var surfaceCamera: String { lang == .chinese ? "相机" : "Camera" }
    static var friendsEmptyTitle: String {
        lang == .chinese ? "还没有和朋友一起拍的房间" : "No stories with friends yet"
    }
    static var friendsEmptyBody: String {
        lang == .chinese
            ? "开一个房间，把邀请码发给朋友。大家拍的片段会剪进同一支片。"
            : "Start a story together and send your friends the code. Everyone's clips go into one film."
    }
    static var inviteFriends: String { lang == .chinese ? "邀请朋友一起拍" : "Invite friends" }

    static var makeRoomVlog: String { lang == .chinese ? "生成 vlog" : "Make vlog" }
    static var roomFeedFilm: String { lang == .chinese ? "拍一段" : "Film a clip" }
    static var roomFeedEmpty: String {
        lang == .chinese ? "还没有人拍。你来拍第一段。" : "Nobody's filmed yet. Be the first."
    }
    static var roomTileNotToday: String { lang == .chinese ? "今天还没拍" : "Not filmed today" }
    static var roomTileNeverFilmed: String { lang == .chinese ? "还没拍过" : "Hasn't filmed yet" }
    static func roomTileLastFilmed(daysAgo: Int) -> String {
        lang == .chinese ? "\(daysAgo) 天没拍了" : "Last filmed \(daysAgo)d ago"
    }
    static var roomTileLike: String { lang == .chinese ? "点赞" : "Like" }
    static var roomTileReply: String { lang == .chinese ? "回复" : "Reply" }
    static var roomTilePoke: String { lang == .chinese ? "拍一拍" : "Poke" }
    static var roomTilePoked: String { lang == .chinese ? "已拍" : "Poked" }
    static var skinTitle: String { lang == .chinese ? "皮肤" : "Theme" }
    static var skinCream: String { lang == .chinese ? "奶油黄" : "Cream" }
    static var skinBlue: String { lang == .chinese ? "经典蓝" : "Classic blue" }
    static var byTimeEntryTitle: String { lang == .chinese ? "按时间拍" : "Film by time" }
    static var byTimeEntryLead: String {
        lang == .chinese ? "不用想题目，看到什么拍什么，按时间排成一支片" : "No prompts. Film what happens; it lines up by time."
    }
    static var writeOwnTitle: String { lang == .chinese ? "自己写" : "Write your own" }
    static var writeOwnLead: String { lang == .chinese ? "列出今天想拍的几件事" : "List what you want to film today" }
    static var aiWriteTitle: String { lang == .chinese ? "AI 帮我写" : "Let AI write it" }
    static var aiWriteLead: String { lang == .chinese ? "说一句今天干嘛，自动列好" : "Say what today is; get a shot list" }
    static var saveToMine: String { lang == .chinese ? "存到我的" : "Save to Mine" }
    static var libraryTitle: String { lang == .chinese ? "所有片段" : "All clips" }
    static var libraryGrid: String { lang == .chinese ? "网格" : "Grid" }
    static var libraryCalendar: String { lang == .chinese ? "日历" : "Calendar" }
    static var librarySelect: String { lang == .chinese ? "选择" : "Select" }
    static var libraryToday: String { lang == .chinese ? "今天" : "Today" }
    static var libraryYesterday: String { lang == .chinese ? "昨天" : "Yesterday" }
    static func libraryClipCount(_ n: Int) -> String { lang == .chinese ? "\(n) 段" : (n == 1 ? "1 clip" : "\(n) clips") }
    static var libraryAllDays: String { lang == .chinese ? "看全部日期" : "All dates" }
    static var libraryEmpty: String {
        lang == .chinese ? "还没有片段。点下面的圆按钮，拍第一段。" : "No clips yet. Tap the round button below to film one."
    }
    static var libraryNothingHere: String {
        lang == .chinese ? "这里没有片段。" : "Nothing here."
    }
    static var libraryUnfiled: String { lang == .chinese ? "未归档" : "Unfiled" }
    static func makeVlog(_ count: Int) -> String {
        lang == .chinese ? "用 \(count) 段生成 vlog" : "Make a vlog from \(count)"
    }
    static var pickClipsHint: String { lang == .chinese ? "点片段来选" : "Tap clips to pick them" }
    static var vlogTitle: String { lang == .chinese ? "我的 vlog" : "My vlog" }
    static var vlogMaking: String { lang == .chinese ? "正在生成 vlog…" : "Making your vlog…" }
    static var vlogFailed: String {
        lang == .chinese ? "生成失败，再试一次。" : "Couldn't make the vlog. Try again."
    }
    static var vlogRetry: String { lang == .chinese ? "重新生成" : "Try again" }
    static var saveVlogToPhotos: String { lang == .chinese ? "存到相册" : "Save to Photos" }
    static var vlogShape: String { lang == .chinese ? "画幅" : "Shape" }
    static var freeformSlot: String { lang == .chinese ? "自由拍摄" : "Free-form" }
    static var fileToPlan: String { lang == .chinese ? "放进选题" : "Add to a topic" }
    static var fileThisClipTo: String { lang == .chinese ? "把这段视频存入…" : "File this clip to…" }
    static func fileToCount(_ count: Int) -> String {
        if lang == .chinese { return count <= 1 ? "存进去" : "存进 \(count) 个" }
        return count <= 1 ? "File it" : "File to \(count)"
    }
    static func landsIn(_ moment: String) -> String {
        lang == .chinese ? "放进「\(moment)」" : "Lands in \(moment)"
    }
    static func filedToCount(_ count: Int) -> String {
        if lang == .chinese { return "已存进 \(count) 个选题" }
        return count == 1 ? "Filed to 1 story" : "Filed to \(count) stories"
    }
    static var pickAtLeastOneStory: String {
        lang == .chinese ? "选一个地方放" : "Pick somewhere to put it"
    }
    static var makePlanFirst: String { lang == .chinese ? "先建一个选题" : "Start a topic first" }
    static func filedTo(_ title: String) -> String {
        lang == .chinese ? "已存入「\(title)」" : "Filed to “\(title)”"
    }
    static var tapToStop: String { lang == .chinese ? "点按停止" : "Tap to stop" }
    static var holdToFilm: String { lang == .chinese ? "按住拍，松手停" : "Hold to film" }
    static var releaseToStop: String { lang == .chinese ? "松手停止" : "Let go to stop" }
    static func clipCap(_ secondsLabel: String) -> String {
        lang == .chinese ? "最长 \(secondsLabel)" : "Up to \(secondsLabel)"
    }
    static var orientationHeader: String { lang == .chinese ? "画幅" : "Orientation" }
    static var orientationPortrait: String { lang == .chinese ? "竖屏" : "Portrait" }
    static var orientationLandscape: String { lang == .chinese ? "横屏" : "Landscape" }
    static var orientationSquare: String { lang == .chinese ? "正方形" : "Square" }
    static var switchOrientation: String { lang == .chinese ? "切换画幅" : "Switch frame" }
    static var flipCamera: String { lang == .chinese ? "切换前后摄像头" : "Flip camera" }
    static var dualCamera: String { lang == .chinese ? "前后同时拍" : "Front and back together" }
    static var cameraFlash: String { lang == .chinese ? "闪光灯" : "Flash" }
    static var cameraStandard: String { lang == .chinese ? "标准" : "Standard" }
    static var cameraCamcorder: String { lang == .chinese ? "DV 机" : "Camcorder" }
    static var cameraFilm: String { lang == .chinese ? "胶片机" : "Film camera" }
    static var cameraInstant: String { lang == .chinese ? "拍立得" : "Instant" }

    static var customZoom: String { lang == .chinese ? "自定义" : "Custom" }
    static var closeCustomZoom: String { lang == .chinese ? "收起自定义倍数" : "Close custom zoom" }
    static func zoomTo(_ value: String) -> String {
        lang == .chinese ? "缩放 \(value)" : "Zoom \(value)"
    }
    static var zoomSlider: String { lang == .chinese ? "缩放倍数" : "Zoom level" }

    static func orientationName(_ orientation: Challenge.Orientation) -> String {
        switch orientation {
        case .portrait: lang == .chinese ? "竖屏" : "portrait"
        case .landscape: lang == .chinese ? "横屏" : "landscape"
        case .square: lang == .chinese ? "正方形" : "square"
        }
    }

    static func noMatchingPlan(_ orientation: Challenge.Orientation) -> String {
        _ = orientation
        return lang == .chinese ? "还没有能放这段的计划，先创建一个" : "No plan fits this clip yet — create one first"
    }

    static var saveAsDraft: String { lang == .chinese ? "先存起来" : "Keep it for now" }
    static var createStoryNow: String { lang == .chinese ? "现在就建个选题" : "Start a topic now" }
    static var noPlaceYet: String { lang == .chinese ? "这段还没有地方放" : "Nowhere to put this yet" }
    static var keepClipQuestion: String { lang == .chinese ? "这段还没归档" : "This clip isn't filed yet" }
    static var keepClip: String { lang == .chinese ? "保留" : "Keep" }
    static var discardClip: String { lang == .chinese ? "丢弃" : "Discard" }
    static var keepClipFootnote: String {
        lang == .chinese
            ? "「保留」会存进「我的」，只有你看得到，之后可以放进选题或发到房间。「丢弃」之后这段就找不回来了。"
            : "Keep puts it in Mine, seen only by you, to send on later. Discard means it's gone."
    }
    static var draftSaveFailed: String {
        lang == .chinese ? "这段没保住，再试一次？" : "Couldn't keep this clip. Try again?"
    }
    static var draftKept: String { lang == .chinese ? "已存进我的" : "Kept in Me" }
    static var draftKeptSeeIt: String { lang == .chinese ? "查看" : "View" }

    static func draftsPending(_ count: Int) -> String {
        lang == .chinese ? "\(count) 段只有我看得到" : "\(count) only you can see"
    }
    static var draftsTitle: String { lang == .chinese ? "只有我" : "Only me" }
    static var draftsEmpty: String {
        lang == .chinese
            ? "没有待归档的片子。录完找不到地方放的时候，会先存到这里。"
            : "Nothing waiting. Clips with nowhere to go get kept here."
    }
    static var archiveDraft: String { lang == .chinese ? "归档到…" : "File to…" }
    static var deleteDraft: String { lang == .chinese ? "删除" : "Delete" }
    static var deleteDraftQuestion: String {
        lang == .chinese ? "删掉这段？删了就找不回来了" : "Delete this clip? It can't be recovered."
    }
    static var draftArchiveFailed: String {
        lang == .chinese ? "没归档成功，片子还在这儿" : "Couldn't file it. The clip is still here."
    }
    static var storyIsFull: String {
        lang == .chinese ? "这个选题满了，没有空位" : "That story is full — no slot left."
    }
    static func noPlaceForDraft(_ orientation: Challenge.Orientation) -> String {
        let kind = orientationName(orientation)
        return lang == .chinese
            ? "还没有\(kind)的选题能放这段"
            : "No \(kind) story can take this yet"
    }
    static func noStoryOfThisFrameYet(_ orientation: Challenge.Orientation) -> String {
        let kind = orientationName(orientation)
        return lang == .chinese
            ? "归档是把这段放进一个同画幅的选题里。你还没有\(kind)的选题——在「\(surfacePlans)」页点「＋ \(surfaceCompose)」建一个，这段就能归档了。"
            : "Filing puts the clip into a story shot the same way round, and you don't have a \(kind) one yet. Tap + \(surfaceCompose) on \(surfacePlans) to make one, and this clip can go in."
    }
    static func everyStoryOfThisFrameIsFull(_ orientation: Challenge.Orientation) -> String {
        let kind = orientationName(orientation)
        return lang == .chinese
            ? "你的\(kind)选题每个瞬间都拍满了，再放就会盖掉已有的片段。新建一个\(kind)选题，或者在已有的选题里删掉一段，这段就有位置了。"
            : "Every moment in your \(kind) stories is already filmed, and filing here would have to overwrite one. Make another \(kind) story, or clear a moment in one of them, and this clip has somewhere to go."
    }
    static func draftSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    static var draftsTotalSize: String {
        lang == .chinese ? "共占用" : "Using"
    }
    static var cameraUnavailable: String { lang == .chinese ? "相机不可用" : "Camera not available" }
    static var retryCamera: String { lang == .chinese ? "重新打开相机" : "Try camera again" }
    static var cameraDeniedTitle: String {
        lang == .chinese ? "没有相机权限" : "No camera access"
    }
    static var cameraDeniedFootnote: String {
        lang == .chinese
            ? "系统只会问一次。到「设置 → 1Day → 相机」打开就可以接着拍。"
            : "iOS only asks once. Turn it on in Settings → 1Day → Camera and you're back."
    }
    static func useDemoClip(_ title: String) -> String {
        lang == .chinese ? "为「\(title)」使用示例片段" : "Use demo clip for \(title)"
    }
    static var openingCamera: String { lang == .chinese ? "正在打开相机" : "Opening camera" }
    static func captureState(recording: Bool, secondsLabel: String) -> String {
        if lang == .chinese { return recording ? "拍摄中 · \(secondsLabel)" : "轻点拍摄" }
        return recording ? "Recording · \(secondsLabel)" : "Tap to capture"
    }
    static func momentPosition(_ index: Int, of total: Int) -> String {
        lang == .chinese ? "第 \(index) 个瞬间，共 \(total) 个" : "Moment \(index) of \(total)"
    }
    static var addCaption: String { lang == .chinese ? "字幕" : "Caption" }
    static var writeOnMoment: String {
        lang == .chinese ? "给这个瞬间写点什么" : "Write on this moment"
    }


    static var rerecord: String { lang == .chinese ? "重录这一天" : "Re-record this day" }
    static var rerecordShort: String { lang == .chinese ? "重拍" : "Retake" }
    static var addTakeShort: String { lang == .chinese ? "再拍一段" : "Add take" }
    static func roomOf(_ name: String) -> String {
        lang == .chinese ? "\(name) 的房间" : "\(name)'s room"
    }
    static func roomOfPeople(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return roomOf(names.first ?? "") }
        let rest = names.dropLast()
        return lang == .chinese
            ? "\(rest.joined(separator: "、")) 和 \(last)"
            : "\(rest.joined(separator: ", ")) and \(last)"
    }
    static var roomNobodyFilmed: String { lang == .chinese ? "还没人拍" : "Nobody's filmed yet" }
    static var thisMoment: String { lang == .chinese ? "这个瞬间" : "This moment" }
    static var captureThisMoment: String {
        lang == .chinese ? "拍下这一刻" : "Capture this moment"
    }
    static func filmNamedMoment(_ title: String) -> String {
        lang == .chinese ? "拍「\(title)」" : "Film \(title)"
    }
    static var notYetFilmed: String { lang == .chinese ? "还没拍" : "Not yet" }
    static var addReaction: String { lang == .chinese ? "加个表情" : "Add a reaction" }
    static var meTitle: String { lang == .chinese ? "设置" : "Settings" }
    static var signedInWithApple: String {
        lang == .chinese ? "已用 Apple ID 登录" : "Signed in with Apple"
    }
    static var statStories: String { lang == .chinese ? "选题" : "Topics" }
    static var statMoments: String { lang == .chinese ? "瞬间" : "Moments" }
    static var statFinished: String { lang == .chinese ? "拍完了" : "Finished" }
    static var anyEmojiPlaceholder: String {
        lang == .chinese ? "或者打任意表情" : "Or type any emoji"
    }
    static var captionAction: String { lang == .chinese ? "加字幕" : "Caption" }
    static var comments: String { lang == .chinese ? "评论" : "Comments" }
    static var firstComment: String {
        lang == .chinese ? "抢个沙发，说点什么吧。" : "Be the first to say something."
    }
    static var addComment: String { lang == .chinese ? "写评论…" : "Add a comment…" }


    static var lookTitle: String { lang == .chinese ? "调色" : "Adjust" }
    static var lookExposure: String { lang == .chinese ? "亮度" : "Exposure" }
    static var lookTemperature: String { lang == .chinese ? "色温" : "Warmth" }
    static var lookContrast: String { lang == .chinese ? "对比" : "Contrast" }
    static var lookReset: String { lang == .chinese ? "复位" : "Reset" }
    static var lookHoldToCompare: String {
        lang == .chinese ? "按住看原片" : "Hold to see the original"
    }
    static var lookRemember: String { lang == .chinese ? "每段都用这个" : "Use on every clip" }


    static var sequence: String { lang == .chinese ? "顺序" : "Sequence" }
    static var saving: String { lang == .chinese ? "保存中…" : "Saving…" }
    static var filmSessionEnded: String {
        lang == .chinese ? "演示已经结束了，这支片子不在了。" : "The demo ended, so this film is gone."
    }
    static var stitchFailed: String { lang == .chinese ? "合成失败" : "Stitching failed" }
    static var yourFilmIsHere: String { lang == .chinese ? "你的影片来了" : "Your film is here" }
    static func reminderBody(_ day: Int) -> String {
        lang == .chinese ? "第 \(day) 天到了，来记录今天的瞬间" : "Day \(day) is here — capture today's moment"
    }
    static func reminderBodyWithPrompt(_ day: Int, _ prompt: String) -> String {
        lang == .chinese ? "第 \(day) 天 · \(prompt) — 来记录今天" : "Day \(day) · \(prompt) — time to capture it"
    }
    static var stitching: String {
        lang == .chinese ? "正在把你的片段合在一起…" : "Stitching your week together…"
    }
    static var photosDenied: String {
        lang == .chinese ? "没有相册权限" : "No Photos access"
    }
    static var savedToPhotos: String { lang == .chinese ? "已保存" : "Saved" }
    static var saveFailed: String {
        lang == .chinese ? "没存进相册，再试一次" : "Couldn't save to Photos. Try again."
    }
    static func titleCardSubtitleOneDay(_ recorded: Int, _ total: Int, secondsLabel: String) -> String {
        lang == .chinese
            ? "一日影片 · \(recorded)/\(total) 个瞬间 · 每段 \(secondsLabel)"
            : "1-day film · \(recorded) of \(total) \(momentWord(total)) · \(secondsLabel) each"
    }


    static var overlays: String { lang == .chinese ? "叠层" : "Overlays" }
    static var openingTitleCard: String { lang == .chinese ? "开场标题卡" : "Opening title card" }
    static var dayCaptions: String { lang == .chinese ? "日期字幕" : "Day captions" }
    static var transition: String { lang == .chinese ? "转场" : "Transition" }
    static var cut: String { lang == .chinese ? "直接切" : "Cut" }
    static var hardCutsFooter: String {
        lang == .chinese ? "0 = 直接切换" : "0 = straight cuts"
    }
    static var adjust: String { lang == .chinese ? "调整" : "Adjust" }

    static var roomNamePlaceholder: String { lang == .chinese ? "给房间起个名字" : "Name this room" }
    static var editPlan: String { lang == .chinese ? "编辑计划" : "Edit plan" }
    static var planTitle: String { lang == .chinese ? "计划名称" : "Plan name" }
    static var captureTitles: String { lang == .chinese ? "拍摄标题" : "Capture titles" }




    static var saveToTemplateLibrary: String {
        lang == .chinese ? "存进我的模板库" : "Save to my template library"
    }


    static var recordTogether: String { lang == .chinese ? "一起记录" : "Record together" }
    static var signInBody: String {
        lang == .chinese
            ? "登录后朋友就能看到每段视频是谁拍的。\n我们只使用你的名字。"
            : "Sign in so friends can see who filmed each clip.\nWe only use your name."
    }
    static var notNow: String { lang == .chinese ? "先不了" : "Not now" }


    static var errorSignInFirst: String {
        lang == .chinese
            ? "先用 Apple 登录，才能和朋友一起拍摄。"
            : "Sign in with Apple first to record with friends."
    }
    static var errorSignedOut: String {
        lang == .chinese
            ? "登录已失效，请重新登录后再和朋友一起拍。"
            : "You're signed out. Sign in again to film with friends."
    }
    static func signInFailure(_ error: Error) -> String {
        if (error as? AuthService.Failure) == .unavailable { return errorNetwork }
        return signInFailed
    }
    static var errorNoRoom: String {
        lang == .chinese
            ? "没有这个邀请码的房间，请和朋友确认一下。"
            : "No room with that code. Double-check it with your friend."
    }
    static var errorNetwork: String {
        lang == .chinese
            ? "连不上 iCloud，检查一下网络再试。"
            : "Can't reach iCloud. Check your connection and try again."
    }
    static var errorRoomCreateFailed: String {
        lang == .chinese
            ? "房间没建起来，过一会儿再试一次。也可以先选自己来。"
            : "Couldn't create the room. Try again in a moment, or record on your own."
    }
    static var sentToRooms: String { lang == .chinese ? "已发送" : "Sent" }
    static var permissionCamera: String { lang == .chinese ? "相机" : "Camera" }
    static var permissionNotifications: String { lang == .chinese ? "通知" : "Notifications" }
    static var errorRoomFull: String { lang == .chinese ? "房间满了，最多 6 人" : "This room is full (6 people max)" }
    static var errorRoomJoinFailed: String {
        lang == .chinese
            ? "进不去这个房间，过一会儿再试一次。"
            : "Couldn't join that room. Try again in a moment."
    }


    static func greeting(name: String?, hour: Int) -> String {
        let part: String
        switch hour {
        case 0..<5: part = lang == .chinese ? "夜深了" : "Still up"
        case 5..<12: part = lang == .chinese ? "早上好" : "Good morning"
        case 12..<18: part = lang == .chinese ? "下午好" : "Good afternoon"
        default: part = lang == .chinese ? "晚上好" : "Good evening"
        }
        guard let name, !name.isEmpty else { return part }
        return lang == .chinese ? "\(part)，\(name)" : "\(part), \(name)"
    }
    static var todaysStory: String { lang == .chinese ? "我的选题" : "My topics" }
    static var resumeStory: String { lang == .chinese ? "接着拍" : "Pick it back up" }
    static var startTodayLabel: String { lang == .chinese ? "今天" : "Today" }
    static var startTodayBody: String {
        lang == .chinese ? "今天还没开始拍" : "Today's story hasn't started"
    }
    static var startTodayCTA: String {
        lang == .chinese ? "今天想拍什么" : "What to film today"
    }
    static var yourStories: String { lang == .chinese ? "你的选题" : "Your topics" }
    static var todayLabel: String { lang == .chinese ? "今天" : "Today" }
    static var yesterdayLabel: String { lang == .chinese ? "昨天" : "Yesterday" }
    static var continueTodaysStory: String {
        lang == .chinese ? "继续拍" : "Continue today's story"
    }
    static var watchYourFilm: String { lang == .chinese ? "看看你的影片" : "Watch your film" }
    static var startTodaysStory: String {
        lang == .chinese ? "今天想拍什么" : "What to film today"
    }
    static var guideTitle: String { lang == .chinese ? "怎么用 1Day" : "How 1Day works" }
    static func mineStats(days: Int, clips: Int) -> String {
        lang == .chinese
            ? "这周拍了 \(days) 天 · 共 \(clips) 段"
            : "\(days == 1 ? "1 day" : "\(days) days") filmed this week · \(clips == 1 ? "1 clip" : "\(clips) clips")"
    }
    static var mineTodayHeader: String { lang == .chinese ? "今天" : "Today" }
    static var mineMakeTodayVlog: String { lang == .chinese ? "拼成今天的 vlog" : "Make today's vlog" }
    static var mineEmptyTitle: String { lang == .chinese ? "今天还没拍" : "Nothing filmed today" }
    static var mineEmptyHint: String {
        lang == .chinese ? "点下面的相机拍几秒，片段会按天出现在这里" : "Tap the camera below and film a few seconds. Clips show up here by day."
    }
    static var dayMakeVlog: String { lang == .chinese ? "做 vlog" : "Make vlog" }
    static var guideSteps: [String] {
        lang == .chinese
            ? ["点相机，拍几秒",
               "拍的都在这里，可以挑几段做 vlog",
               "去「房间」建房间，发邀请码"]
            : ["Tap the camera below and film a few seconds.",
               "Everything you film lands in Mine — pick a few clips to make a vlog.",
               "To film with friends, open a room in Rooms and send them the code."]
    }
    static var sharedLabel: String { lang == .chinese ? "共享" : "Shared" }
    static func momentsShort(_ total: Int) -> String {
        lang == .chinese ? "\(total) 个瞬间" : "\(total) \(momentWord(total))"
    }
    static func templateRuntime(count: Int, secondsLabel: String) -> String {
        lang == .chinese ? "每段 \(secondsLabel)" : "\(secondsLabel) each"
    }
    static var youLabel: String { lang == .chinese ? "你" : "You" }
    static var yoursLabel: String { lang == .chinese ? "自建" : "Yours" }
    static func openMomentLabel(_ moment: String) -> String {
        lang == .chinese ? "还没拍：\(moment)" : "Still open: \(moment)"
    }
    static func storyCardCaption(open: String, isComplete: Bool) -> String {
        if isComplete { return lang == .chinese ? "影片已经准备好了" : "Your film is ready" }
        return openMomentLabel(open)
    }
    static func filmReadySubtitle(duration: String) -> String {
        lang == .chinese ? "影片完成 · \(duration)" : "Film ready · \(duration)"
    }
    static var noPrompts: String { lang == .chinese ? "无题目" : "No prompts" }


    static var composerSetupStep: String { lang == .chinese ? "设置" : "Setup" }
    static var newStoryQuestion: String {
        lang == .chinese ? "今天想拍什么？" : "What do you want to film today?"
    }
    static var captionGestureHint: String {
        lang == .chinese
            ? "拖动移位置 · 两指捏大小 · 两指转角度"
            : "Drag to move · Pinch to resize · Twist to turn"
    }
    static var deleteCaptionAction: String {
        lang == .chinese ? "删除字幕" : "Delete caption"
    }
    static var captionDeleted: String { lang == .chinese ? "字幕已删除" : "Caption deleted" }
    static var undo: String { lang == .chinese ? "撤销" : "Undo" }
    static func captionTintName(_ tint: CaptionSticker.Tint) -> String {
        let zh = lang == .chinese
        return switch tint {
        case .white: zh ? "白色" : "White"
        case .black: zh ? "黑色" : "Black"
        case .blue: zh ? "蓝色" : "Blue"
        case .cyan: zh ? "青色" : "Cyan"
        case .mint: zh ? "薄荷绿" : "Mint"
        case .butter: zh ? "奶油黄" : "Butter yellow"
        case .coral: zh ? "珊瑚色" : "Coral"
        case .rose: zh ? "玫瑰色" : "Rose"
        case .lavender: zh ? "薰衣草紫" : "Lavender"
        case .violet: zh ? "紫罗兰" : "Violet"
        case .blush: zh ? "浅粉" : "Blush"
        case .ink: zh ? "墨蓝" : "Ink"
        }
    }
    static var captionResizeHandle: String {
        lang == .chinese ? "缩放和旋转字幕" : "Resize and rotate caption"
    }
    static var captionPlateSample: String { lang == .chinese ? "字" : "Aa" }
    static func captionPlateName(_ style: CaptionSticker.Style) -> String {
        switch style {
        case .outline, .headline: lang == .chinese ? "不加底" : "No backing"
        case .band: lang == .chinese ? "半透明黑底" : "Dimmed backing"
        case .solid: lang == .chinese ? "纯黑底" : "Solid backing"
        case .light: lang == .chinese ? "白底" : "Light backing"
        }
    }
    static var captionEditAction: String { lang == .chinese ? "改字幕" : "Edit caption" }
    static var chatShort: String { lang == .chinese ? "聊天" : "Chat" }
    static func avatarColourN(_ number: Int) -> String {
        lang == .chinese ? "头像颜色 \(number)" : "Avatar colour \(number)"
    }


    static func continueDayLabel(_ day: Int) -> String {
        lang == .chinese ? "接着拍 · 第 \(day) 天" : "Continue · Day \(day)"
    }
    static var deleteMoment: String { lang == .chinese ? "删除这个瞬间" : "Delete this moment" }
    static func catchUpDayLabel(day: Int, moment: String) -> String {
        lang == .chinese ? "补第 \(day) 天 · \(moment)" : "Catch up day \(day) · \(moment)"
    }

    static var openSystemSettings: String {
        lang == .chinese ? "打开系统设置" : "Open Settings"
    }

    static var coverFromClips: String {
        lang == .chinese ? "从拍好的片段里选" : "From what you filmed"
    }
    static func nextReminderAt(_ when: String) -> String {
        lang == .chinese ? "下一次提醒：\(when)" : "Next reminder: \(when)"
    }
    static var reminderNothingToNudge: String {
        lang == .chinese
            ? "今天没有要提醒的选题 —— 建一个就会排上"
            : "Nothing to remind you about yet — start a story and it'll queue up"
    }
    static var reminderBlocked: String {
        lang == .chinese
            ? "系统里关掉了通知，到「设置 › 通知 › 1Day」打开"
            : "Notifications are off in iOS Settings › Notifications › 1Day"
    }
    static var followPrompts: String {
        lang == .chinese ? "跟着题目拍" : "Follow prompts"
    }
    static var recordByTime: String {
        lang == .chinese ? "按时间拍" : "Record by time"
    }
    static var rackByTime: String {
        lang == .chinese ? "按时间" : "By time"
    }
    static var rackCustom: String {
        lang == .chinese ? "自己写" : "Your own"
    }
    static var storySettingsTitle: String {
        lang == .chinese ? "选题设置" : "Topic settings"
    }
    static var startFilmingCTA: String {
        lang == .chinese ? "拍出今天的一天" : "Film today"
    }
    static var noCustomTemplatesYet: String {
        lang == .chinese
            ? "还没有自己写的题目。写一组，它就留在这里。"
            : "No prompt sets of your own yet. Write one and it stays here."
    }
    static var customPromptsTitle: String {
        lang == .chinese ? "自己写题目" : "Write your own prompts"
    }
    static var customPromptsLead: String {
        lang == .chinese
            ? "写一句今天的安排，自动列出要拍的瞬间"
            : "Describe today in a line and get a list of shots"
    }
    static var timeOnlySetupTitle: String {
        lang == .chinese ? "只记录时间" : "Time only"
    }
    static var timeOnlyMoment: String {
        lang == .chinese ? "拍下这一刻" : "Film this moment"
    }
    static var timeOnlyReminder: String {
        lang == .chinese
            ? "现在的你在做什么？留两秒给这一刻。"
            : "What are you doing right now? Keep two seconds of it."
    }
    static var next: String { lang == .chinese ? "下一步" : "Next" }
    static var back: String { lang == .chinese ? "返回" : "Back" }
    static var whoIsFilming: String { lang == .chinese ? "谁来拍" : "Who's filming" }
    static var createByYourself: String { lang == .chinese ? "自己来" : "By yourself" }
    static var createByYourselfCaption: String {
        lang == .chinese ? "只在这台设备上" : "Stays on this device"
    }
    static var createWithFriendsCaption: String {
        lang == .chinese ? "分享邀请码一起拍" : "Share a code, film together"
    }
    static var storyNameLabel: String { lang == .chinese ? "选题名字" : "Topic name" }


    static func theMoments(_ count: Int) -> String {
        lang == .chinese ? "\(count) 个瞬间" : "The moments · \(count)"
    }
    static var reviewMoments: String { lang == .chinese ? "查看/编辑" : "Review" }
    static var hideMoments: String { lang == .chinese ? "收起" : "Hide" }
    static var addMoment: String { lang == .chinese ? "加一个瞬间" : "Add a moment" }
    static var writeYourOwn: String { lang == .chinese ? "写自己的" : "Write your own" }
    static var useTheseMoments: String { lang == .chinese ? "就用这些" : "Use these" }
    static var guidedHeading: String {
        lang == .chinese ? "想拍什么，由你来写" : "Write what you might want to film"
    }
    static var guidedNamePlaceholder: String {
        lang == .chinese ? "给这一天起个名字…" : "Name this day…"
    }
    static var storyNameNeeded: String {
        lang == .chinese ? "先给选题起个名字" : "Give the topic a name first"
    }

    static var intentHeading: String {
        lang == .chinese ? "说说今天要干嘛" : "What's today for?"
    }
    static var intentPlaceholder: String {
        lang == .chinese ? "比如：今天要搬家" : "For example: moving house today"
    }
    static var suggestPrompts: String { lang == .chinese ? "出题目" : "Suggest prompts" }
    static var suggestingPrompts: String { lang == .chinese ? "生成中…" : "Generating…" }
    static var suggestAnotherSet: String { lang == .chinese ? "换一批" : "Try another set" }
    static var retry: String { lang == .chinese ? "重试" : "Retry" }
    static func useTheseMomentsCount(_ count: Int) -> String {
        lang == .chinese ? "就用这些（\(count) 个）" : "Use these (\(count))"
    }
    static var suggestFailed: String {
        lang == .chinese ? "没连上" : "Couldn't connect"
    }
    static var suggestRateLimited: String {
        lang == .chinese ? "等一分钟再试" : "Try again in a minute"
    }

    static var yourPrompts: String { lang == .chinese ? "想拍的画面" : "Scenes to film" }
    static var chooseFromPromptLibrary: String {
        lang == .chinese ? "从提示库里选" : "Choose from the prompt library"
    }
    static func customPromptPlaceholder(_ index: Int) -> String {
        let chineseExamples = ["例如：出门前", "例如：今天这一餐", "例如：回家以后"]
        let englishExamples = ["For example: before leaving", "For example: today's meal", "For example: back home"]
        let examples = lang == .chinese ? chineseExamples : englishExamples
        return examples[(index - 1) % examples.count]
    }


    static var everyonesMoments: String {
        lang == .chinese ? "大家的瞬间" : "Everyone's moments"
    }
    static var tapToFilm: String { lang == .chinese ? "点一下开拍" : "Tap to film" }
    static var clipLengthRow: String { lang == .chinese ? "每段最长" : "Longest clip" }
    static var orientationRow: String { lang == .chinese ? "画面方向" : "Frame" }
    static var inviteLabel: String { lang == .chinese ? "邀请" : "Invite" }
    static var sendTheCodeTitle: String {
        lang == .chinese ? "把邀请码发出去" : "Send the code out"
    }
    static var sendTheCodeNow: String {
        lang == .chinese ? "现在发" : "Send it now"
    }
    static var sendTheCodeLater: String {
        lang == .chinese ? "待会儿" : "Later"
    }
    static var stitchingMoment: String {
        lang == .chinese ? "正在拼接这个瞬间…" : "Stitching this moment…"
    }
    static var appearance: String { lang == .chinese ? "外观" : "Appearance" }
    static var systemAppearance: String { lang == .chinese ? "跟随系统" : "System" }
    static var lightAppearance: String { lang == .chinese ? "浅色" : "Light" }
    static var darkAppearance: String { lang == .chinese ? "深色" : "Dark" }
    static var displayAndLanguage: String {
        lang == .chinese ? "显示与语言" : "Display & Language"
    }
    static var inviteCodeLabel: String { lang == .chinese ? "邀请码" : "Invite code" }
    static var noCodeOnClipboard: String {
        lang == .chinese ? "剪贴板里没有邀请码" : "No invite code on the clipboard"
    }
    static func previewTheFilm(_ count: Int) -> String {
        lang == .chinese ? "预览 · \(count) 个瞬间" : "Preview · \(count) \(momentWord(count))"
    }

    static var dayIsFull: String { lang == .chinese ? "这一天拍满了" : "The day is full" }
    static var watchTheFilm: String { lang == .chinese ? "看成片" : "See the film" }
    static func filmFromMoments(_ moments: Int) -> String {
        lang == .chinese
            ? "\(moments) 个瞬间，一支片"
            : "\(moments) \(momentWord(moments)), one film"
    }
    static func momentFilmedBy(_ title: String, names: [String]) -> String {
        let who = nameList(Array(names.prefix(3)), overflow: max(names.count - 3, 0))
        return lang == .chinese ? "\(title)，\(who)拍的" : "\(title), filmed by \(who)"
    }
    static func slotPosition(_ slot: Int, of total: Int) -> String {
        lang == .chinese ? "第 \(slot) 个，共 \(total) 个" : "\(slot) of \(total)"
    }
    static var chatLabel: String { lang == .chinese ? "聊天" : "Chat" }
    static var startHere: String { lang == .chinese ? "先拍这个？" : "Start here?" }
    static var filmThisOne: String { lang == .chinese ? "开拍" : "Film it" }
    static var addYourTake: String { lang == .chinese ? "加上你的" : "Add yours" }
    static var watchThisMoment: String {
        lang == .chinese ? "看这个瞬间" : "Watch this moment"
    }
    static var retrySync: String { lang == .chinese ? "重新同步" : "Retry sync" }
    static var moreLabel: String { lang == .chinese ? "更多" : "More" }


    static func peopleInRoom(_ count: Int) -> String {
        guard count > 1 else {
            return lang == .chinese ? "只有你在这个房间" : "Just you in this room"
        }
        return lang == .chinese ? "\(count) 人在这个房间" : "\(count) people in this room"
    }

    static func roomColumnClipCount(_ count: Int) -> String {
        if lang == .chinese { return "\(count) 段" }
        return count == 1 ? "1 clip" : "\(count) clips"
    }
    static var roomColumnEmpty: String {
        lang == .chinese ? "还没拍过" : "Nothing yet"
    }
    static func roomReminderBody(prompt: String?) -> String {
        guard let prompt, !prompt.isEmpty else {
            return lang == .chinese ? "房间在等你拍一段" : "Your room is waiting for a clip"
        }
        return lang == .chinese ? "\(prompt) — 来拍一段" : "\(prompt) — film a clip"
    }

    static func roomWhoFilmed(_ names: [String], overflow: Int, mineToo: Bool) -> String {
        guard !names.isEmpty || overflow > 0 else {
            return mineToo
                ? (lang == .chinese ? "只有你拍了" : "You're the only one so far")
                : (lang == .chinese ? "还没有人拍" : "Nobody has filmed yet")
        }
        let who = nameList(names, overflow: overflow)
        if mineToo {
            return lang == .chinese ? "你和\(who)拍了" : "You and \(who) have filmed"
        }
        return lang == .chinese ? "\(who)拍了，就差你" : "\(who) filmed — just you left"
    }

    static func roomWaitingOn(_ names: [String], overflow: Int) -> String {
        let who = nameList(names, overflow: overflow)
        return lang == .chinese ? "在等 \(who)" : "Waiting on \(who)"
    }

    private static func nameList(_ names: [String], overflow: Int) -> String {
        var parts = names
        if overflow > 0 {
            parts.append(
                lang == .chinese
                    ? "另外 \(overflow) 人"
                    : (overflow == 1 ? "1 other" : "\(overflow) others"))
        }
        guard parts.count > 1 else { return parts.first ?? "" }
        let last = parts.removeLast()
        let head = parts.joined(separator: lang == .chinese ? "、" : ", ")
        return lang == .chinese ? "\(head)和\(last)" : "\(head) and \(last)"
    }


    static var chatSignInToJoin: String {
        lang == .chinese ? "登录并加入房间后才能聊天。" : "Sign in and join the room to chat."
    }
    static var chatLocalDemoBanner: String {
        lang == .chinese ? "本地演示 · 不会发送给朋友" : "Local demo · Nothing is sent to friends"
    }
    static var chatEmpty: String {
        lang == .chinese ? "在这里聊聊今天拍的" : "Talk about your story here"
    }
    static var chatTitle: String { lang == .chinese ? "聊天" : "Chat" }
    static func chatClipEvent(name: String, moment: String?) -> String {
        let base = lang == .chinese ? "\(name) 拍了一段" : "\(name) filmed a clip"
        guard let moment, !moment.isEmpty else { return base }
        return "\(base) · \(moment)"
    }
    static var chatDeleteTitle: String { lang == .chinese ? "删除这条消息？" : "Delete this message?" }
    static var chatDeleteMessage: String { lang == .chinese ? "删除消息" : "Delete message" }
    static var chatDeleteForEveryone: String {
        lang == .chinese ? "大家那边也会删掉" : "It'll be removed for everyone"
    }
    static var chatSending: String { lang == .chinese ? "发送中" : "Sending" }
    static var chatDeleting: String { lang == .chinese ? "正在删除" : "Deleting" }
    static var chatFailedRetry: String { lang == .chinese ? "发送失败 · 重试" : "Failed · Retry" }
    static func chatAbout(_ moment: String) -> String {
        lang == .chinese ? "在说：\(moment)" : "About: \(moment)"
    }
    static var chatRemoveContext: String { lang == .chinese ? "取消引用" : "Remove context" }
    static var chatPlaceholder: String { lang == .chinese ? "发消息…" : "Message…" }
    static var chatSend: String { lang == .chinese ? "发送" : "Send" }
    static var chatErrorStorage: String {
        lang == .chinese ? "聊天记录没存上，再试一次" : "Couldn't save the chat. Try again."
    }
    static var chatErrorFetch: String {
        lang == .chinese ? "没连上" : "Couldn't connect"
    }
    static var chatErrorSend: String {
        lang == .chinese ? "有消息没发出去，点它下面的重试" : "A message didn't send. Tap Retry under it."
    }
    static var chatErrorDelete: String {
        lang == .chinese ? "没删掉" : "Couldn't delete"
    }
    static func chatErrorTooLong(_ limit: Int) -> String {
        lang == .chinese
            ? "最多 \(limit) 字"
            : "Messages max out at \(limit) characters. Your text is still here."
    }


    static var generatingTitle: String {
        lang == .chinese ? "正在做片子" : "Making your film"
    }
    static func mergedProgress(_ done: Int, total: Int) -> String {
        lang == .chinese ? "已合成 \(done)/\(total) 个瞬间" : "\(done) of \(total) moments merged"
    }
    static var stepCollecting: String {
        lang == .chinese ? "收集瞬间" : "Collecting moments"
    }
    static var stepTransitions: String {
        lang == .chinese ? "加入转场" : "Adding transitions"
    }
    static var stepFinishing: String {
        lang == .chinese ? "导出" : "Exporting"
    }


    static var filmReadyTitle: String {
        lang == .chinese ? "片子好了" : "Your film's ready"
    }
    static func filmMeta(duration: String, clips: Int, people: Int) -> String {
        lang == .chinese
            ? "\(duration) · \(clips) 段 · \(people) 人"
            : "\(duration) · \(clips == 1 ? "1 clip" : "\(clips) clips") · \(people == 1 ? "1 person" : "\(people) people")"
    }
    static var filmAdjustTitle: String { lang == .chinese ? "调整成片" : "Adjust the film" }
    static var filmAdjustSummary: String { lang == .chinese ? "声音、谁在里面、画面" : "Sound, who's in it, look" }
    static var filmLookRow: String { lang == .chinese ? "画面：柔和度、亮度、暖度" : "Look: softness, brightness, warmth" }
    static var filmFailedTryAgain: String {
        lang == .chinese ? "没做出来" : "Couldn't make the film"
    }
    static var savedLabel: String { lang == .chinese ? "已保存" : "Saved" }
    static var sampleCantSaveOrShare: String {
        lang == .chinese ? "示例里不能保存和分享" : "Saving and sharing are off in the sample"
    }
    static var wholeDayHeader: String { lang == .chinese ? "完整的一天" : "The whole day" }
    static var saveAction: String { lang == .chinese ? "保存" : "Save" }
    static var shareAction: String { lang == .chinese ? "分享" : "Share" }
    static var durationLabel: String { lang == .chinese ? "时长" : "Duration" }
    static var momentsLabel: String { lang == .chinese ? "瞬间" : "Moments" }
    static var peopleLabel: String { lang == .chinese ? "参与者" : "People" }
    static var rebuildFilm: String { lang == .chinese ? "重新生成" : "Rebuild film" }


    static var account: String { lang == .chinese ? "账号" : "Account" }
    static var about: String { lang == .chinese ? "关于" : "About" }
    static var version: String { lang == .chinese ? "版本" : "Version" }
    static var privacyPolicy: String { lang == .chinese ? "隐私政策" : "Privacy Policy" }
    static var yourNamePlaceholder: String {
        lang == .chinese ? "朋友看到的名字" : "What friends see"
    }
    static var defaultMemberName: String { lang == .chinese ? "朋友" : "Friend" }
    static var notSignedIn: String {
        lang == .chinese ? "未登录" : "Not signed in"
    }
    static var signIn: String { lang == .chinese ? "登录" : "Sign in" }
    static var signOut: String { lang == .chinese ? "退出登录" : "Sign out" }
    static var signOutConfirmTitle: String {
        lang == .chinese ? "退出登录？" : "Sign out?"
    }
    static var signOutConfirmMessage: String {
        lang == .chinese
            ? "房间会先隐藏，重新登录就回来"
            : "Shared rooms will be hidden on this device until you sign back in. Your own stories stay put."
    }
    static var avatarColourLabel: String { lang == .chinese ? "头像颜色" : "Avatar colour" }
    static var editNameHint: String { lang == .chinese ? "修改名字" : "Edit name" }
    static var deleteAccount: String { lang == .chinese ? "删除账号" : "Delete account" }
    static var deleteAccountTitle: String {
        lang == .chinese ? "删除账号和所有内容？" : "Delete your account and everything in it?"
    }
    static var deleteAccountWarning: String {
        lang == .chinese
            ? "这会永久删除这台设备上的全部选题和片段，以及你在共享房间里上传的片段、回应和评论。朋友们自己的片段会保留，但你的名字会被移除。此操作无法撤销。"
            : "This permanently removes every story and clip on this device, plus the clips, reactions and comments you added to shared rooms. Your friends keep their own clips, but your name is removed. This cannot be undone."
    }
    static var deleteAccountConfirm: String {
        lang == .chinese ? "永久删除" : "Delete permanently"
    }
    static var deletingAccount: String { lang == .chinese ? "正在删除…" : "Deleting…" }
    static var deleteAccountFailedTitle: String {
        lang == .chinese ? "没有删干净" : "Not fully deleted"
    }
    static var deleteAccountFailedMessage: String {
        lang == .chinese
            ? "还有一部分没删掉，连上网再试一次会接着删"
            : "The connection dropped and some of your records are still in the cloud. Nothing on this device has been touched. Try again when you're back online and it will pick up where it stopped."
    }
    static var deletedMemberName: String {
        lang == .chinese ? "已注销的用户" : "A former member"
    }
}
