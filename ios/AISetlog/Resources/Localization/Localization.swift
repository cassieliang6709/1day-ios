import Foundation
import SwiftUI

// MARK: - Language

/// The language choices offered in Settings. `.system` follows the device;
/// the others force a language regardless of the device locale.
///
/// Adding a language:
/// 1. Add a case here, plus its `localeCode` and native `displayName`.
/// 2. Extend `resolved(locale:)` if the system mapping needs it.
/// 3. Add an arm for it in each `Strings` entry (missing ones fall back to
///    English) and in `LocalizedText` translations.
/// 4. Add a `<lang>.lproj/InfoPlist.strings` for the permission prompts and
///    the region to `knownRegions` in project.yml.
/// The Settings picker picks the new case up automatically via `CaseIterable`.
/// Light / dark / follow the system, chosen in Settings.
///
/// The app is a light-first design, so "follow the system" is the default but
/// not the only sensible answer — someone who keeps iOS in dark mode may still
/// want this one bright, and vice versa.
enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }

    /// UserDefaults key, shared with the `@AppStorage` the views bind to.
    static let storageKey = "appAppearance"

    /// nil hands the decision back to the system.
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

    /// UserDefaults key, shared with the `@AppStorage` the views bind to.
    static let storageKey = "appLanguage"

    /// Dictionary key used in `LocalizedText.translations`. BCP-47-ish.
    var localeCode: String {
        switch self {
        case .system: Locale.current.language.languageCode?.identifier ?? "en"
        case .english: "en"
        case .chinese: "zh-Hans"
        }
    }

    /// Specific languages show their native name (iOS convention); only
    /// "System" is translated.
    var displayName: String {
        switch self {
        case .system: Strings.systemLanguage
        case .english: "English"
        case .chinese: "中文"
        }
    }

    /// Collapses `.system` to a concrete language using a locale.
    func resolved(locale: Locale = .current) -> AppLanguage {
        guard self == .system else { return self }
        return locale.language.languageCode?.identifier == "zh" ? .chinese : .english
    }

    /// Convenience for the common device-locale case.
    var resolved: AppLanguage { resolved() }

    /// Locale used by date/time formatters and SwiftUI controls when the app
    /// language is explicitly overridden in Settings.
    var locale: Locale { Locale(identifier: resolved.localeCode) }

    /// The concrete language the app should render in right now.
    static var effective: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        return stored.resolved()
    }
}

// MARK: - LocalizedText

/// A string with a translation per language, keyed by `localeCode`. Codable so
/// it can live inside a saved custom template; resolves at display time.
/// Missing translations fall back to English, so a new language can ship
/// incrementally.
struct LocalizedText: Codable, Equatable, Hashable {
    var translations: [String: String]

    init(en: String, zh: String) {
        translations = ["en": en, "zh-Hans": zh]
    }

    init(translations: [String: String]) {
        self.translations = translations
    }

    /// Convenience accessors — kept so existing readers (reverseIndex,
    /// template identity) don't care about the storage shape.
    var en: String { translations["en"] ?? translations.values.first ?? "" }
    var zh: String { translations["zh-Hans"] ?? en }

    func resolved(_ lang: AppLanguage = .effective) -> String {
        translations[lang.resolved.localeCode]
            ?? translations["en"]
            ?? translations.values.first
            ?? ""
    }

    // Back-compat decoding: pre-multi-language builds stored `{en, zh}`.
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

// MARK: - Strings catalog

/// Every user-facing UI string, in one place. Interpolated strings are
/// functions so each language controls its own word order.
///
/// Convention: a view that renders a `Strings.*` value must hold
/// `@AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system`
/// — even if it never reads it — because that binding is what re-renders the
/// view when the language changes.
///
/// Adding a language: add one arm per entry. Anything left out falls back to
/// English via the `default` arm.
enum Strings {
    private static var lang: AppLanguage { AppLanguage.effective.resolved }

    // MARK: Common

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
    static var languageFootnote: String {
        lang == .chinese
            ? "“跟随系统”会使用设备语言。模板、拍摄提示和菜单会立即切换。"
            : "“System” follows your device language. Templates, prompts, and menus switch instantly."
    }

    static var notifications: String { lang == .chinese ? "通知" : "Notifications" }
    static var eveningReminder: String {
        lang == .chinese ? "晚间拍摄提醒" : "Evening capture reminder"
    }
    static var eveningReminderFooter: String {
        lang == .chinese
            ? "每天最多一条。当天已经拍完就不会提醒。"
            : "At most one each day. Completed moments are never reminded."
    }
    static var reminderTime: String { lang == .chinese ? "提醒时间" : "Reminder time" }
    static var friendActivity: String { lang == .chinese ? "好友动态" : "Friend activity" }
    static var friendActivityFooter: String {
        lang == .chinese
            ? "好友上传片段、评论或回应时通知你。相近动态会合并。"
            : "Get notified for friends’ clips, comments, and reactions. Nearby activity is bundled."
    }
    static var showFriendNames: String {
        lang == .chinese ? "在通知中显示好友名字" : "Show friend names in notifications"
    }
    static var sharedRooms: String { lang == .chinese ? "共享挑战" : "Shared challenges" }
    static var notificationPermissionDenied: String {
        lang == .chinese
            ? "系统通知已关闭。请到 iPhone 设置中允许 1Day 通知。"
            : "Notifications are off in iPhone Settings. Allow notifications for 1Day to use this."
    }
    static var openSettings: String { lang == .chinese ? "打开系统设置" : "Open Settings" }
    static var notificationPrimerTitle: String {
        lang == .chinese ? "留住今天的瞬间？" : "Keep today’s moment?"
    }
    static var notificationPrimerBody: String {
        lang == .chinese
            ? "每天最多一次，在你选择的时间提醒你。拍完后不会再提醒。"
            : "Get at most one reminder at your chosen time. Once you record, it stays quiet."
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
    static func roomClipActivity(name: String?, day: Int) -> String {
        if lang == .chinese {
            return name.map { "\($0) 刚上传了第 \(day) 天的片段。" }
                ?? "朋友刚上传了第 \(day) 天的片段。"
        }
        return name.map { "\($0) just added their Day \(day) clip." }
            ?? "A friend just added their Day \(day) clip."
    }
    static func roomCommentActivity(name: String?) -> String {
        if lang == .chinese {
            return name.map { "\($0) 评论了你们的片段。" } ?? "朋友评论了你们的片段。"
        }
        return name.map { "\($0) commented on your shared film." }
            ?? "A friend commented on your shared film."
    }
    static func roomReactionActivity(name: String?) -> String {
        if lang == .chinese {
            return name.map { "\($0) 回应了你们的片段。" } ?? "朋友回应了你们的片段。"
        }
        return name.map { "\($0) reacted to your shared film." }
            ?? "A friend reacted to your shared film."
    }

    // MARK: Models

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

    static func storyLabel(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "一日影片" : "七日挑战" }
        return oneDay ? "1-day film" : "7-day challenge"
    }

    static func clipLengthName(_ length: Challenge.ClipLength) -> String {
        switch length {
        case .tiny: lang == .chinese ? "超短" : "Tiny"
        case .story: lang == .chinese ? "故事" : "Story"
        case .scene: lang == .chinese ? "场景" : "Scene"
        }
    }

    static func clipLengthCaption(_ length: Challenge.ClipLength) -> String {
        switch length {
        case .tiny: lang == .chinese ? "一眨眼就好" : "Blink-and-done"
        case .story: lang == .chinese ? "多一点余味" : "A fuller beat"
        case .scene: lang == .chinese ? "让它慢下来" : "Let it breathe"
        }
    }

    static func fullTitle7Days(_ name: String) -> String {
        lang == .chinese ? "7 天\(name)" : "7 Days of \(name)"
    }

    // MARK: Home

    static var startToday: String { lang == .chinese ? "开始今天" : "Start today" }
    static var enterInviteCode: String { lang == .chinese ? "输入邀请码" : "Enter invite code" }
    static var newStory: String { lang == .chinese ? "新建故事" : "New story" }
    /// Home header progress, beside the date: "今天 1/7".
    static func headerDateProgress(_ recorded: Int, _ total: Int) -> String {
        lang == .chinese ? "今天 \(recorded)/\(total)" : "Today \(recorded)/\(total)"
    }
    static var couldntJoin: String { lang == .chinese ? "无法加入" : "Couldn't join" }
    static var leaveRoom: String { lang == .chinese ? "退出房间" : "Leave room" }
    static var deleteChallenge: String { lang == .chinese ? "删除挑战" : "Delete challenge" }
    static var history: String { lang == .chinese ? "历史" : "HISTORY" }
    static var joining: String { lang == .chinese ? "加入中…" : "Joining…" }
    static func todayIs(_ date: String) -> String {
        lang == .chinese ? "今天是\(date)。" : "Today is \(date)."
    }
    static var startNewFilm: String { lang == .chinese ? "开始一部新影片？" : "Start a new film?" }
    static var tagline: String {
        lang == .chinese ? "7 个瞬间，一支小短片。" : "7 moments. One tiny vlog."
    }
    static var haveInviteCode: String { lang == .chinese ? "我有邀请码" : "I have an invite code" }
    static var firstRunHeadline: String {
        lang == .chinese ? "把今天，留成一支片" : "Turn today into one film"
    }
    static var firstRunThreeMoments: String {
        lang == .chinese ? "个两秒瞬间" : "two-second moments"
    }
    static var firstRunOneFilm: String {
        lang == .chinese ? "支属于你的短片" : "film that is yours"
    }
    static var firstRunEquationAccessibility: String {
        lang == .chinese ? "三个两秒瞬间，成为一支属于你的短片" : "Three two-second moments become one film that is yours"
    }
    static var firstRunGuide: String {
        lang == .chinese
            ? "选一个故事 · 拍 3 个瞬间 · 1Day 为你做成影片"
            : "Choose a story · film 3 moments · 1Day makes the film"
    }
    static var firstRunStart: String {
        lang == .chinese ? "开始我的第一支片" : "Start my first film"
    }
    static var firstRunStartHint: String {
        lang == .chinese ? "创建一支包含三个瞬间的个人短片。" : "Creates a personal film with three moments."
    }
    static var firstRunJoin: String {
        lang == .chinese ? "有邀请码？加入朋友" : "Have an invite? Join friends"
    }
    static var firstRunSampleFilmAccessibility: String {
        lang == .chinese ? "1Day 示例影片预览" : "1Day sample film preview"
    }
    static var firstRunSampleFilmPlay: String {
        lang == .chinese ? "播放示例影片" : "Play sample film"
    }
    static var firstRunSampleFilmPause: String {
        lang == .chinese ? "暂停示例影片" : "Pause sample film"
    }
    static var quickStartTitle: String { lang == .chinese ? "我的一天" : "My day" }
    static var onboardingSkip: String { lang == .chinese ? "跳过" : "Skip" }
    static var onboardingNext: String { lang == .chinese ? "下一步" : "Next" }
    static func onboardingPage(_ page: Int, total: Int) -> String {
        lang == .chinese ? "\(page) / \(total)" : "\(page) of \(total)"
    }
    static var onboardingCaptureTitle: String {
        lang == .chinese ? "先留住一个小瞬间" : "Capture one small moment"
    }
    static var onboardingCaptureBody: String {
        lang == .chinese
            ? "不用拍一整天。两秒钟，就够记住当下。"
            : "You do not need to film all day. Two seconds is enough to hold onto this moment."
    }
    static var onboardingFilmTitle: String {
        lang == .chinese ? "七个瞬间，自动成为一部影片" : "Seven moments become one film"
    }
    static var onboardingFilmBody: String {
        lang == .chinese
            ? "1Day 会在设备端按顺序合成片段，不需要你剪辑。"
            : "1Day assembles every clip in order, on your device. No editing required."
    }
    static var onboardingTogetherTitle: String {
        lang == .chinese ? "自己记录，也可以和朋友一起" : "Keep it yours—or share it"
    }
    static var onboardingTogetherBody: String {
        lang == .chinese
            ? "个人故事只保存在设备上；共享故事通过 iCloud 邀请你信任的人。"
            : "Solo stories stay on your device. Shared stories use iCloud with people you invite."
    }
    static var createFirstStory: String {
        lang == .chinese ? "创建我的第一个故事" : "Create my first story"
    }
    static var startAnotherStory: String {
        lang == .chinese ? "开始一个新故事" : "Start a new story"
    }
    static var inviteHint: String {
        lang == .chinese ? "向朋友要 6 位邀请码。" : "Ask your friend for the 6-character code."
    }
    static var joinRoomButton: String { lang == .chinese ? "加入今日房间" : "Join today's room" }

    static func completedOn(_ date: String) -> String {
        lang == .chinese ? "已完成 · \(date)" : "Completed · \(date)"
    }
    static func completedRange(_ range: String) -> String {
        lang == .chinese ? "已完成 · \(range)" : "Completed · \(range)"
    }
    static func oneDayProgress(
        _ recorded: Int,
        total: Int,
        secondsLabel: String
    ) -> String {
        lang == .chinese
            ? "\(recorded)/\(total) 个瞬间 · 每段 \(secondsLabel) · 24 小时影片"
            : "\(recorded)/\(total) \(secondsLabel) moments · 24-hour film"
    }
    static func friendsRange(_ count: Int, _ range: String) -> String {
        lang == .chinese ? "\(count) 位朋友 · \(range)" : "\(count) friends · \(range)"
    }
    static func endedRecorded(_ recorded: Int, total: Int) -> String {
        lang == .chinese
            ? "已结束 · 已录 \(recorded)/\(total)"
            : "Ended · \(recorded)/\(total) recorded"
    }
    static func dayOfRange(_ day: Int, total: Int, _ range: String) -> String {
        lang == .chinese
            ? "第 \(day) 天，共 \(total) 天 · \(range)"
            : "Day \(day) of \(total) · \(range)"
    }
    static var todayTitle: String { lang == .chinese ? "今天" : "Today" }
    static var todaySubtitle: String {
        lang == .chinese ? "记录两秒，拼出你的一天。" : "Capture two seconds. Build your day."
    }
    static var nextCapture: String { lang == .chinese ? "下一个瞬间" : "Next capture" }
    static func slotOfTotal(oneDay: Bool, index: Int, total: Int) -> String {
        if lang == .chinese { return oneDay ? "第 \(index) 个瞬间，共 \(total) 个" : "第 \(index) 天，共 \(total) 天" }
        return oneDay ? "Moment \(index) of \(total)" : "Day \(index) of \(total)"
    }
    /// The hero card's single CTA: which slot + how long, in one button.
    static func recordSlot(oneDay: Bool, index: Int, secondsLabel: String) -> String {
        if lang == .chinese {
            return oneDay ? "记录第 \(index) 个瞬间 · \(secondsLabel)" : "记录第 \(index) 天 · \(secondsLabel)"
        }
        return oneDay ? "Record moment \(index) · \(secondsLabel)" : "Record Day \(index) · \(secondsLabel)"
    }
    static var activeStories: String { lang == .chinese ? "进行中的故事" : "Active stories" }
    static var seeAll: String { lang == .chinese ? "查看全部" : "See all" }
    static var comingSoon: String { lang == .chinese ? "即将上线" : "Coming soon" }

    // MARK: New challenge

    static func headerTitle(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "今天的\n一日故事？" : "你的\n七日故事？" }
        return oneDay ? "What's your\n1-day story?" : "What's your\n7-day story?"
    }
    static func sevenDayHeaderSubtitle(secondsLabel: String) -> String {
        lang == .chinese
            ? "每天 \(secondsLabel)，七天后合成一部片子。"
            : "\(secondsLabel) a day. One film at the end."
    }
    static func titlePrompt(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "我的一日故事…" : "我的七日目标…" }
        return oneDay ? "My 1-day story..." : "My 7-day goal..."
    }
    static var formatHeader: String { lang == .chinese ? "形式" : "FORMAT" }
    static var modeOneDay: String { lang == .chinese ? "一日" : "1-Day" }
    static var modeSevenDay: String { lang == .chinese ? "七日" : "7-Day" }
    static var clipLengthHeader: String { lang == .chinese ? "片段时长" : "CLIP LENGTH" }
    static func pickScriptHeader(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "选今天的脚本" : "或选个主题" }
        return oneDay ? "PICK TODAY'S SCRIPT" : "OR PICK A VIBE"
    }
    static func templateMomentCount(_ count: Int, secondsLabel: String) -> String {
        lang == .chinese
            ? "\(count) 个瞬间，每个 \(secondsLabel)"
            : "\(count) moments, \(secondsLabel) each"
    }
    static var selectedLabel: String { lang == .chinese ? "已选" : "Selected" }
    static var tapToSelect: String {
        lang == .chinese ? "点一下选这个脚本" : "Tap to select this script"
    }
    static var deleteTemplate: String { lang == .chinese ? "删除模板" : "Delete template" }
    static var editTemplate: String { lang == .chinese ? "编辑模板" : "Edit template" }
    static var buildYourOwn: String { lang == .chinese ? "自己搭一个" : "Build your own" }
    static var pickYourPrompts: String {
        lang == .chinese ? "挑选拍摄提示" : "Pick your own prompts"
    }
    static var whosIn: String { lang == .chinese ? "谁参与" : "WHO'S IN" }
    static var justMe: String { lang == .chinese ? "只有我" : "Just me" }
    static var privateWeek: String { lang == .chinese ? "私密的一周" : "A private week" }
    static var withFriends: String { lang == .chinese ? "和朋友一起" : "With friends" }
    static var roomInvite: String { lang == .chinese ? "房间 + 邀请码" : "Room + invite code" }
    static var createRoom: String { lang == .chinese ? "创建房间" : "Create room" }
    static var startMoment1: String { lang == .chinese ? "开始第 1 个瞬间" : "Start Moment 1" }
    static var startDay1: String { lang == .chinese ? "开始第 1 天" : "Start Day 1" }
    static func promptN(_ number: Int) -> String {
        lang == .chinese ? "第 \(number) 个拍摄标题" : "Capture title \(number)"
    }

    // MARK: Board

    static func createFilm(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "生成一日影片" : "生成每周影片" }
        return oneDay ? "Create 1-day film" : "Create weekly film"
    }
    static func previewFilm(_ recorded: Int, _ total: Int, unitPlural: String) -> String {
        lang == .chinese
            ? "预览影片 · \(recorded)/\(total) \(unitPlural)"
            : "Preview film · \(recorded)/\(total) \(unitPlural)"
    }
    static func previewSharedFilm(_ clips: Int) -> String {
        lang == .chinese ? "预览共同影片 · \(clips) 个片段" : "Preview shared film · \(clips) clips"
    }
    static func membersInRoom(_ count: Int) -> String {
        lang == .chinese ? "房间里有 \(count) 人" : "\(count) in this room"
    }
    static var friend: String { lang == .chinese ? "朋友" : "Friend" }
    static func sharedClips(_ count: Int) -> String {
        lang == .chinese ? "共同片段 · \(count)" : "Shared clips · \(count)"
    }
    static func invitePill(hasClips: Bool) -> String {
        if lang == .chinese { return hasClips ? "发送今日邀请 · 邀请码 " : "邀请朋友 · 邀请码 " }
        return hasClips ? "Send today's invite · code " : "Invite friends · code "
    }
    static func shareMessageCaptured(first: String, title: String, code: String) -> String {
        lang == .chinese
            ? "我刚在 1Day 为「\(title)」拍下了\(first)。快来加入我的挑战！邀请码：\(code)\noneday://join?code=\(code)"
            : "I just captured \(first) for “\(title)” on 1Day. Join my challenge! Code: \(code)\noneday://join?code=\(code)"
    }
    static func shareMessageInvite(title: String, code: String) -> String {
        lang == .chinese
            ? "来 1Day 加入我的「\(title)」挑战！邀请码：\(code)\noneday://join?code=\(code)"
            : "Join my “\(title)” challenge on 1Day! Code: \(code)\noneday://join?code=\(code)"
    }
    static var allClipsIn: String {
        lang == .chinese ? "片段齐了 — 可以成片了。" : "All clips in - time to make the film."
    }
    static func recordedProgress(
        _ recorded: Int,
        total: Int,
        secondsLabel: String,
        unitPlural: String
    ) -> String {
        lang == .chinese
            ? "\(total) \(unitPlural)中已录 \(recorded) 段（\(secondsLabel)）"
            : "\(recorded) of \(total) \(secondsLabel) \(unitPlural) recorded"
    }
    static var oneDayComplete: String { lang == .chinese ? "一日影片完成" : "1-day film complete" }
    static func momentCount(_ total: Int) -> String {
        lang == .chinese ? "24 小时，\(total) 个瞬间" : "\(total) moments in 24 hours"
    }
    static var weekComplete: String { lang == .chinese ? "本周完成" : "Week complete" }
    static func dayOf(_ day: Int, total: Int) -> String {
        lang == .chinese ? "第 \(day) 天，共 \(total) 天" : "Day \(day) of \(total)"
    }
    static var record: String { lang == .chinese ? "拍摄" : "Record" }
    static var catchUp: String { lang == .chinese ? "补拍" : "Catch up" }
    static func lockedSlot(oneDay: Bool, day: Int) -> String {
        if lang == .chinese { return oneDay ? "第 \(day) 个瞬间" : "第 \(day) 天" }
        return oneDay ? "Moment \(day)" : "Day \(day)"
    }

    // MARK: Record

    static var retake: String { lang == .chinese ? "重拍" : "Retake" }
    static var useClip: String { lang == .chinese ? "使用这段" : "Use clip" }
    static var surfacePlans: String { lang == .chinese ? "计划" : "Plans" }
    static var surfaceCamera: String { lang == .chinese ? "拍摄" : "Camera" }
    static var freeformSlot: String { lang == .chinese ? "自由拍摄" : "Free-form" }
    static var fileToPlan: String { lang == .chinese ? "存入计划" : "File to a plan" }
    static var fileThisClipTo: String { lang == .chinese ? "把这段视频存入…" : "File this clip to…" }
    static var makePlanFirst: String { lang == .chinese ? "先在计划页创建一个计划" : "Make a plan first in Plans" }
    static func filedTo(_ title: String) -> String {
        lang == .chinese ? "已存入「\(title)」" : "Filed to “\(title)”"
    }
    static var tapToStop: String { lang == .chinese ? "点按停止" : "Tap to stop" }
    static var orientationHeader: String { lang == .chinese ? "画幅" : "Orientation" }
    static var orientationPortrait: String { lang == .chinese ? "竖屏" : "Portrait" }
    static var orientationLandscape: String { lang == .chinese ? "横屏" : "Landscape" }
    static var switchOrientation: String { lang == .chinese ? "切换横竖屏" : "Switch orientation" }
    static var flipCamera: String { lang == .chinese ? "切换前后摄像头" : "Flip camera" }
    static func noMatchingPlan(landscape: Bool) -> String {
        let kind = landscape
            ? (lang == .chinese ? "横屏" : "landscape")
            : (lang == .chinese ? "竖屏" : "portrait")
        return lang == .chinese ? "没有\(kind)计划，先创建一个" : "No \(kind) plan yet — create one first"
    }

    // Drafts: what a clip does when there's nowhere to file it yet.
    static var saveAsDraft: String { lang == .chinese ? "先存起来" : "Keep it for now" }
    static var createStoryNow: String { lang == .chinese ? "现在就建个故事" : "Start a story now" }
    static var noPlaceYet: String { lang == .chinese ? "这段还没有地方放" : "Nowhere to put this yet" }
    static var keepClipQuestion: String { lang == .chinese ? "这段还没归档" : "This clip isn't filed yet" }
    static var keepClip: String { lang == .chinese ? "保留" : "Keep" }
    static var discardClip: String { lang == .chinese ? "丢弃" : "Discard" }
    static var draftSaveFailed: String {
        lang == .chinese ? "这段没保住，再试一次？" : "Couldn't keep this clip. Try again?"
    }
    static var draftKept: String { lang == .chinese ? "已存起来" : "Kept for later" }

    // Drafts: the list they live in until they're filed.
    static func draftsPending(_ count: Int) -> String {
        lang == .chinese ? "\(count) 段待归档" : "\(count) waiting to be filed"
    }
    static var draftsTitle: String { lang == .chinese ? "待归档" : "Waiting to be filed" }
    static var draftsEmpty: String {
        lang == .chinese
            ? "没有待归档的片子。录完找不到地方放的时候，会先存到这里。"
            : "Nothing waiting. Clips with nowhere to go get kept here."
    }
    static var archiveDraft: String { lang == .chinese ? "归档到…" : "File to…" }
    static var deleteDraft: String { lang == .chinese ? "删除" : "Delete" }
    static var draftArchiveFailed: String {
        lang == .chinese ? "没归档成功，片子还在这儿" : "Couldn't file it. The clip is still here."
    }
    /// No matching story for this clip's frame, from inside the drafts list —
    /// where "retake" isn't an option, so it says what would help instead.
    static func noPlaceForDraft(landscape: Bool) -> String {
        let kind = lang == .chinese
            ? (landscape ? "横屏" : "竖屏")
            : (landscape ? "landscape" : "portrait")
        return lang == .chinese
            ? "还没有\(kind)的故事能放这段"
            : "No \(kind) story can take this yet"
    }
    /// Rounded file size, so someone can see which drafts are worth deleting.
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
    static func useDemoClip(_ title: String) -> String {
        lang == .chinese ? "为「\(title)」使用示例片段" : "Use demo clip for \(title)"
    }
    static var openingCamera: String { lang == .chinese ? "正在打开相机" : "Opening camera" }
    static func captureState(recording: Bool, secondsLabel: String) -> String {
        if lang == .chinese { return recording ? "拍摄中 · \(secondsLabel)" : "轻点拍摄" }
        return recording ? "Recording · \(secondsLabel)" : "Tap to capture"
    }
    static var capturedLabel: String { lang == .chinese ? "已拍摄" : "CAPTURED" }
    static func momentN(_ day: Int) -> String {
        lang == .chinese ? "瞬间 \(day)" : "MOMENT \(day)"
    }
    static var dailyFilm: String { lang == .chinese ? "每日影片" : "daily film" }
    static var addCaption: String { lang == .chinese ? "加一句字幕" : "add a caption" }
    static var writeOnMoment: String {
        lang == .chinese ? "给这个瞬间写点什么" : "Write on this moment"
    }

    // MARK: Clip preview

    static func capturedAt(_ date: String) -> String {
        lang == .chinese ? "拍摄于 \(date)" : "Captured \(date)"
    }
    static var rerecord: String { lang == .chinese ? "重录这一天" : "Re-record this day" }
    static var comments: String { lang == .chinese ? "评论" : "Comments" }
    static func commentsCount(_ count: Int) -> String {
        lang == .chinese ? "评论 · \(count)" : "Comments · \(count)"
    }
    static var firstComment: String {
        lang == .chinese ? "抢个沙发，说点什么吧。" : "Be the first to say something."
    }
    static var addComment: String { lang == .chinese ? "写评论…" : "Add a comment…" }

    // MARK: Final reel

    static var sequence: String { lang == .chinese ? "顺序" : "Sequence" }
    static var saving: String { lang == .chinese ? "保存中…" : "Saving…" }
    static var saveVideo: String { lang == .chinese ? "保存视频" : "Save video" }
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
    static var renderedOnDevice: String {
        lang == .chinese ? "正在设备上生成影片" : "Rendering on this device"
    }
    static func filmTitle(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "一日影片" : "每周影片" }
        return oneDay ? "1-Day Film" : "Weekly Film"
    }
    static func footerSequence(_ count: Int, unit: String) -> String {
        if lang == .chinese { return "\(count) 个片段 · 交叉淡入淡出" }
        return "\(count) \(unit)\(count == 1 ? "" : "s") · crossfades"
    }
    static func shareFilm(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "分享一日影片" : "分享每周影片" }
        return oneDay ? "Share 1-day film" : "Share weekly film"
    }
    static var photosDenied: String {
        lang == .chinese ? "需要相册权限才能保存视频。" : "Photos access is needed to save the video."
    }
    static var savedToPhotos: String { lang == .chinese ? "已保存到相册。" : "Saved to Photos." }
    static func saveFailed(_ error: String) -> String {
        lang == .chinese ? "保存视频失败：\(error)" : "Couldn't save video: \(error)"
    }
    static func titleCardSubtitleOneDay(_ recorded: Int, _ total: Int, secondsLabel: String) -> String {
        lang == .chinese
            ? "一日影片 · \(recorded)/\(total) 个瞬间 · 每段 \(secondsLabel)"
            : "1-day film · \(recorded)/\(total) \(secondsLabel) moments"
    }

    // MARK: Adjust sheet

    static var overlays: String { lang == .chinese ? "叠层" : "Overlays" }
    static var openingTitleCard: String { lang == .chinese ? "开场标题卡" : "Opening title card" }
    static var dayCaptions: String { lang == .chinese ? "日期字幕" : "Day captions" }
    static var transition: String { lang == .chinese ? "转场" : "Transition" }
    static var cut: String { lang == .chinese ? "硬切" : "Cut" }
    static var hardCutsFooter: String {
        lang == .chinese ? "0 = 硬切，日记感更利落。" : "0 = hard cuts for a snappier diary film."
    }
    static var adjust: String { lang == .chinese ? "调整" : "Adjust" }

    static var editPlan: String { lang == .chinese ? "编辑计划" : "Edit plan" }
    static var planTitle: String { lang == .chinese ? "计划名称" : "Plan name" }
    static var captureTitles: String { lang == .chinese ? "拍摄标题" : "Capture titles" }
    static func editPlanFootnote(shared: Bool) -> String {
        if lang == .chinese {
            return shared
                ? "修改会保存到这台设备，不会更改朋友设备上的标题。"
                : "已经拍摄的视频不会被删除，只会更新之后显示的标题。"
        }
        return shared
            ? "Changes stay on this device and do not rename titles on your friends’ devices."
            : "Existing clips stay in place; only their displayed titles change."
    }

    // MARK: Build template

    static func yourOrder(_ count: Int) -> String {
        lang == .chinese ? "你的顺序（\(count)）" : "YOUR ORDER (\(count))"
    }
    static var promptPool: String { lang == .chinese ? "提示词库" : "PROMPT POOL" }
    static var nameYourTemplate: String {
        lang == .chinese ? "给模板起个名字" : "Name your template"
    }

    // MARK: Sign in

    static var recordTogether: String { lang == .chinese ? "一起记录" : "Record together" }
    static var signInBody: String {
        lang == .chinese
            ? "登录后朋友就能看到每段视频是谁拍的。\n我们只使用你的名字。"
            : "Sign in so friends can see who filmed each clip.\nWe only use your name."
    }
    static var notNow: String { lang == .chinese ? "先不了" : "Not now" }

    // MARK: Errors (stores / services)

    static var errorSignInFirst: String {
        lang == .chinese
            ? "先用 Apple 登录，才能和朋友一起拍摄。"
            : "Sign in with Apple first to record with friends."
    }
    static var errorICloud: String {
        lang == .chinese
            ? "请登录 iCloud（设置 ▸ 你的名字）才能和朋友一起拍摄。"
            : "Sign into iCloud (Settings ▸ your name) to record with friends."
    }
    static var errorNoRoom: String {
        lang == .chinese
            ? "没有这个邀请码的房间，请和朋友确认一下。"
            : "No room with that code. Double-check it with your friend."
    }
    static var errorIndexDeploying: String {
        lang == .chinese
            ? "房间还没准备好 — CloudKit 索引还在部署中。"
            : "Room isn't set up yet — the CloudKit index is still deploying."
    }

    // MARK: Plans home

    /// Time-of-day greeting. The name is optional — a solo user never signs in.
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
    static var greetingQuestion: String {
        lang == .chinese ? "今天会是什么故事？" : "What story will today be?"
    }
    static var todaysStory: String { lang == .chinese ? "今天的故事" : "Today's story" }
    /// Used instead of `todaysStory` when nothing was started today but
    /// something is still unfinished — saying "today's story" then would be a
    /// lie about what the card is.
    static var resumeStory: String { lang == .chinese ? "接着拍" : "Pick it back up" }
    static var startTodayLabel: String { lang == .chinese ? "今天" : "Today" }
    static var startTodayBody: String {
        lang == .chinese ? "还没开始今天的故事" : "Today's story hasn't started"
    }
    static var startTodayCTA: String {
        lang == .chinese ? "开始今天的故事" : "Start today's story"
    }
    /// Heads the reverse-chronological list below today's story. Replaces the
    /// old "your other plans" / "finished films" split, which sorted by state
    /// and so couldn't answer "what did I film on the 31st".
    static var scrollBack: String { lang == .chinese ? "往前翻" : "Earlier" }
    /// Used instead of "scroll back" when today's own stories are in the list —
    /// "scroll back" sitting directly above a row labelled "today" reads as a
    /// small lie about what's underneath it.
    static var yourStories: String { lang == .chinese ? "你的故事" : "Your stories" }
    static var todayLabel: String { lang == .chinese ? "今天" : "Today" }
    static var yesterdayLabel: String { lang == .chinese ? "昨天" : "Yesterday" }
    static var continueTodaysStory: String {
        lang == .chinese ? "继续今天的故事" : "Continue today's story"
    }
    static var watchYourFilm: String { lang == .chinese ? "看看你的影片" : "Watch your film" }
    static var startTodaysStory: String {
        lang == .chinese ? "开始今天的故事" : "Start today's story"
    }
    static var noStoryTitle: String {
        lang == .chinese ? "今天还没有故事" : "No story yet today"
    }
    static var noStoryBody: String {
        lang == .chinese
            ? "选一种心情，拍下几个小瞬间，1Day 会把它们变成一部影片。"
            : "Pick a mood, film a few tiny moments, and 1Day turns them into one film."
    }
    static var sharedLabel: String { lang == .chinese ? "共享" : "Shared" }
    /// Chip-length moment count. `momentCount` is a full sentence and blows a
    /// capsule out to four lines.
    static func momentsShort(_ total: Int) -> String {
        lang == .chinese ? "\(total) 个瞬间" : "\(total) moments"
    }
    /// "2s each" — the per-clip length on a template card.
    static func templateRuntime(count: Int, secondsLabel: String) -> String {
        lang == .chinese ? "每段 \(secondsLabel)" : "\(secondsLabel) each"
    }
    static var youLabel: String { lang == .chinese ? "你" : "You" }
    static var yoursLabel: String { lang == .chinese ? "自建" : "Yours" }
    static func nextUpMoment(_ moment: String) -> String {
        lang == .chinese ? "接下来：\(moment)" : "Next: \(moment)"
    }
    static func storyCardCaption(next: String, isComplete: Bool) -> String {
        if isComplete { return lang == .chinese ? "影片已经准备好了" : "Your film is ready" }
        return nextUpMoment(next)
    }
    static func filmReadySubtitle(duration: String) -> String {
        lang == .chinese ? "影片完成 · \(duration)" : "Film ready · \(duration)"
    }
    static var customTemplateBlurb: String {
        lang == .chinese ? "你自己写的小脚本。" : "Your own little script."
    }
    static var noPrompts: String { lang == .chinese ? "无题目" : "No prompts" }

    // MARK: Story composer

    static var composerMoodStep: String { lang == .chinese ? "选个心情" : "Pick a mood" }
    static var composerSetupStep: String { lang == .chinese ? "设置" : "Set it up" }
    static var newStoryQuestion: String {
        lang == .chinese ? "今天会是什么故事？" : "What will today's story be?"
    }
    static var recordingStyleSubtitle: String {
        lang == .chinese
            ? "跟着题目拍，或者按时间随手拍。"
            : "Follow prompts, or just record as the day goes."
    }
    /// The two halves of the one pill selector at the top of the screen. They
    /// filter what's below; they are not themselves a thing you "pick", which
    /// is why they're pills and not two posters the size of the templates.
    static var followPrompts: String {
        lang == .chinese ? "跟着题目拍" : "Follow prompts"
    }
    static var recordByTime: String {
        lang == .chinese ? "按时间拍" : "Record by time"
    }
    static var customPromptsTitle: String {
        lang == .chinese ? "自己写题目" : "Write your own prompts"
    }
    static var customPromptsCaption: String {
        lang == .chinese
            ? "先写几个想拍的，之后随时可以改"
            : "Start with a few ideas. You can change them anytime."
    }
    static var pickPromptSet: String {
        lang == .chinese ? "选一组题目" : "Pick a set of prompts"
    }
    static var sevenDayChallenges: String {
        lang == .chinese ? "七日挑战" : "Seven-day challenges"
    }
    static var moreTemplates: String {
        lang == .chinese ? "更多模板" : "More templates"
    }
    /// How many prompts the chosen template will ask for, beside its name.
    static func promptCountLabel(_ count: Int) -> String {
        lang == .chinese ? "\(count) 个题目" : "\(count) prompts"
    }
    /// The whole of the "record by time" state. It replaces the grid rather
    /// than dimming it — showing a wall of things you can't tap was a patch,
    /// not an answer.
    static var timeOnlyCardBody: String {
        lang == .chinese
            ? "没有题目。拍到的每一段按时间排好，发生什么拍什么。"
            : "No prompts. Every clip lands in the order you filmed it."
    }
    static var timeOnlyCaptionNote: String {
        lang == .chinese
            ? "字幕由你自己在每段片子上填写，1Day 只负责保留拍摄时间。"
            : "You write the captions on each clip; 1Day just keeps the time."
    }
    static func composerSubtitle(count: Int, secondsLabel: String) -> String {
        lang == .chinese
            ? "\(count) 个瞬间，每个 \(secondsLabel)，合成一部小影片。"
            : "\(count) moments, \(secondsLabel) each. One tiny film."
    }
    static var timeOnlyComposerSubtitle: String {
        lang == .chinese ? "不设题目，按时间留住这一天。" : "No prompts. Keep the day as it happens."
    }
    static var timeOnlySetupTitle: String {
        lang == .chinese ? "只记录时间" : "Time only"
    }
    static var timeOnlySetupBody: String {
        lang == .chinese
            ? "拍下当下，1Day 会自动保留拍摄时间；画面上的文字由每个人自己填写。"
            : "Film the moment and 1Day keeps its time. Everyone can write their own caption."
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
    static var soloSetupSubtitle: String {
        lang == .chinese ? "几个小设置，今天就开始。" : "A few details, then today begins."
    }
    static var createByYourself: String { lang == .chinese ? "自己来" : "By yourself" }
    static var createByYourselfCaption: String {
        lang == .chinese ? "只在这台设备上" : "Stays on this device"
    }
    static var createWithFriendsCaption: String {
        lang == .chinese ? "分享邀请码一起拍" : "Share a code, film together"
    }
    static var createRoomSubtitle: String {
        lang == .chinese ? "一起完成今天的故事。" : "Build today's story together."
    }
    static var roomExplainer: String {
        lang == .chinese
            ? "大家在一天里各自拍下瞬间，1Day 把它们缝成一部影片。"
            : "Everyone captures moments through the day. 1Day stitches them into one beautiful film."
    }
    static var scriptLabel: String { lang == .chinese ? "脚本" : "Script" }
    static var storyNameLabel: String { lang == .chinese ? "故事名字" : "Story name" }
    static var createStoryCTA: String { lang == .chinese ? "创建故事" : "Create story" }

    // MARK: Moments (composer)

    static var theMoments: String { lang == .chinese ? "七个瞬间" : "The moments" }
    static var reviewMoments: String { lang == .chinese ? "查看/编辑" : "Review" }
    static var hideMoments: String { lang == .chinese ? "收起" : "Hide" }
    static var addMoment: String { lang == .chinese ? "加一个瞬间" : "Add a moment" }
    static var writeYourOwn: String { lang == .chinese ? "写自己的" : "Write your own" }
    /// Entry point from the poster rack into the guided flow.
    static var writeYourOwnMoments: String {
        lang == .chinese ? "自己写题目" : "Write your own prompts"
    }
    static var useTheseMoments: String { lang == .chinese ? "就用这些" : "Use these" }
    static var guidedHeading: String {
        lang == .chinese ? "想拍什么，由你来写" : "Write what you might want to film"
    }
    static var guidedSubtitle: String {
        lang == .chinese
            ? "先写两个可能遇见的画面就够了。今天真正开始以后，随时还能增加或修改。"
            : "Start with two scenes you might encounter. Add or change them anytime once the day begins."
    }
    static var guidedNamePlaceholder: String {
        lang == .chinese ? "给这一天起个名字…" : "Name this day…"
    }
    static func guidedFootnote(filled: Int) -> String {
        lang == .chinese
            ? "已经写了 \(filled) 个。2–7 个都可以，空白项不会加入故事。"
            : "\(filled) written. Use 2–7 prompts; blank rows won't be added to the story."
    }
    // MARK: Prompts from one sentence

    static var intentHeading: String {
        lang == .chinese ? "说说今天要干嘛" : "What's today for?"
    }
    static var intentSubtitle: String {
        lang == .chinese
            ? "一句话就行。题目会填进下面的列表，每条都能改。"
            : "One sentence is enough. The prompts fill the list below, and every one is editable."
    }
    static var intentPlaceholder: String {
        lang == .chinese ? "比如：今天要搬家" : "For example: moving house today"
    }
    static var suggestPrompts: String { lang == .chinese ? "出题目" : "Suggest prompts" }
    static var suggestingPrompts: String { lang == .chinese ? "在想…" : "Thinking…" }
    /// Not an error dialog: the thing they were doing still works, and the list
    /// is right there. This only explains why nothing appeared.
    static var suggestFailed: String {
        lang == .chinese ? "这次没出来，先自己写吧。" : "Nothing came back — write your own."
    }
    static var suggestRateLimited: String {
        lang == .chinese ? "出得有点勤，等会儿再试。" : "That's a lot of asking. Try again later."
    }

    static var yourPrompts: String { lang == .chinese ? "想拍的画面" : "Scenes to film" }
    static var addAnotherPrompt: String {
        lang == .chinese ? "再加一个题目" : "Add another prompt"
    }
    static var chooseFromPromptLibrary: String {
        lang == .chinese ? "从提示库里选" : "Choose from the prompt library"
    }
    static var promptLibrary: String { lang == .chinese ? "提示库" : "Prompt library" }
    static func customPromptPlaceholder(_ index: Int) -> String {
        let chineseExamples = ["例如：出门前", "例如：今天这一餐", "例如：回家以后"]
        let englishExamples = ["For example: before leaving", "For example: today's meal", "For example: back home"]
        let examples = lang == .chinese ? chineseExamples : englishExamples
        return examples[(index - 1) % examples.count]
    }

    // MARK: Timeline

    static var everyonesMoments: String {
        lang == .chinese ? "大家的瞬间" : "Everyone's moments"
    }
    static var viewTimeline: String { lang == .chinese ? "时间线视图" : "Timeline view" }
    static var viewGrid: String { lang == .chinese ? "网格视图" : "Grid view" }
    static var tapToFilm: String { lang == .chinese ? "点一下开拍" : "Tap to film" }
    /// Row labels. `clipLengthHeader` / `orientationHeader` are the older
    /// all-caps section headers and wrap awkwardly inside an `OptionRow`.
    static var clipLengthRow: String { lang == .chinese ? "片段时长" : "Clip length" }
    static var orientationRow: String { lang == .chinese ? "画面方向" : "Frame" }
    static func waitingForMoment(_ name: String) -> String {
        lang == .chinese ? "等 \(name) 的瞬间…" : "Waiting for \(name)'s moment…"
    }
    static var inviteLabel: String { lang == .chinese ? "邀请" : "Invite" }
    static var stitchingMoment: String {
        lang == .chinese ? "正在拼接这个瞬间…" : "Stitching this moment…"
    }
    static var appearance: String { lang == .chinese ? "外观" : "Appearance" }
    static var systemAppearance: String { lang == .chinese ? "跟随系统" : "System" }
    static var lightAppearance: String { lang == .chinese ? "浅色" : "Light" }
    static var darkAppearance: String { lang == .chinese ? "深色" : "Dark" }
    static var appearanceFootnote: String {
        lang == .chinese
            ? "只影响 1Day，不改变系统设置。"
            : "Applies to 1Day only — your system setting is untouched."
    }
    static var inviteCodeLabel: String { lang == .chinese ? "邀请码" : "Invite code" }
    static var inviteCodeCopied: String { lang == .chinese ? "已复制" : "Copied" }
    static var makeTheFilm: String { lang == .chinese ? "生成影片" : "Make the film" }
    static func previewTheFilm(_ count: Int) -> String {
        lang == .chinese ? "预览 · \(count) 个瞬间" : "Preview · \(count) moments"
    }
    static var timelineEmptyHint: String {
        lang == .chinese
            ? "第一个瞬间会出现在这条时间线的顶端。"
            : "Your first moment lands at the top of this line."
    }

    // MARK: Generating

    static var generatingTitle: String {
        lang == .chinese ? "正在生成今天的影片 ✨" : "Making today's film ✨"
    }
    static var generatingSubtitle: String {
        lang == .chinese ? "把你的一天缝在一起" : "Auto-stitching your day"
    }
    static func mergedProgress(_ done: Int, total: Int) -> String {
        lang == .chinese ? "已合成 \(done)/\(total) 个瞬间" : "\(done) of \(total) moments merged"
    }
    static var stepCollecting: String {
        lang == .chinese ? "收集瞬间" : "Collecting moments"
    }
    static var stepSyncing: String {
        lang == .chinese ? "同步大家的片段" : "Syncing everyone's clips"
    }
    static var stepTransitions: String {
        lang == .chinese ? "加入转场" : "Adding transitions"
    }
    static var stepFinishing: String {
        lang == .chinese ? "生成你的故事" : "Creating your story"
    }
    static var stitchingCare: String {
        lang == .chinese ? "正在细心缝合 ✨" : "Stitching with care ✨"
    }
    static var stitchingCareBody: String {
        lang == .chinese
            ? "加上柔和的转场，还有刚刚好的气氛。"
            : "Adding smooth transitions and the right vibes."
    }

    // MARK: Final film

    static var filmReadyTitle: String {
        lang == .chinese ? "影片准备好了 🎉" : "Your 1Day film is ready 🎉"
    }
    static var filmReadyBody: String {
        lang == .chinese ? "属于你这一天的小影片。" : "A beautiful film of your day."
    }
    static var wholeDayHeader: String { lang == .chinese ? "完整的一天" : "The whole day" }
    static var saveAction: String { lang == .chinese ? "保存" : "Save" }
    static var shareAction: String { lang == .chinese ? "分享" : "Share" }
    static var exportAction: String { lang == .chinese ? "导出" : "Export" }
    static var durationLabel: String { lang == .chinese ? "时长" : "Duration" }
    static var momentsLabel: String { lang == .chinese ? "瞬间" : "Moments" }
    static var peopleLabel: String { lang == .chinese ? "参与者" : "People" }
    static var rebuildFilm: String { lang == .chinese ? "重新生成" : "Rebuild film" }

    // MARK: Account

    static var account: String { lang == .chinese ? "账号" : "Account" }
    static var about: String { lang == .chinese ? "关于" : "About" }
    static var version: String { lang == .chinese ? "版本" : "Version" }
    static var privacyPolicy: String { lang == .chinese ? "隐私政策" : "Privacy Policy" }
    static var signedInAs: String { lang == .chinese ? "已登录" : "Signed in as" }
    static var notSignedIn: String {
        lang == .chinese ? "未登录（只有共享故事需要登录）" : "Not signed in — only shared stories need it"
    }
    static var signOut: String { lang == .chinese ? "退出登录" : "Sign out" }
    static var deleteAccount: String { lang == .chinese ? "删除账号" : "Delete account" }
    static var deleteAccountTitle: String {
        lang == .chinese ? "删除账号和所有内容？" : "Delete your account and everything in it?"
    }
    static var deleteAccountWarning: String {
        lang == .chinese
            ? "这会永久删除这台设备上的全部故事和片段，以及你在共享房间里上传的片段、回应和评论。朋友们自己的片段会保留，但你的名字会被移除。此操作无法撤销。"
            : "This permanently removes every story and clip on this device, plus the clips, reactions and comments you added to shared rooms. Your friends keep their own clips, but your name is removed. This cannot be undone."
    }
    static var deleteAccountConfirm: String {
        lang == .chinese ? "永久删除" : "Delete permanently"
    }
    static var deleteAccountFootnote: String {
        lang == .chinese
            ? "退出登录只是登出，故事仍留在设备上。删除账号会清空一切。"
            : "Signing out just signs you out; your stories stay on this device. Deleting removes everything."
    }
    static var deletingAccount: String { lang == .chinese ? "正在删除…" : "Deleting…" }
    /// Replaces a departed creator's name on a room their friends still use.
    static var deletedMemberName: String {
        lang == .chinese ? "已注销的用户" : "A former member"
    }
}
