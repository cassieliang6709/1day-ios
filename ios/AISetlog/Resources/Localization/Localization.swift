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
    /// Sits under the friend-activity switch as a summary of the room list one
    /// level down, so you can tell at a glance whether anything is muted.
    static var allRoomsOn: String { lang == .chinese ? "都开着" : "All on" }
    static func roomsMuted(_ count: Int) -> String {
        lang == .chinese ? "静音了 \(count) 个" : "\(count) muted"
    }
    static var sharedRoomsFooter: String {
        lang == .chinese
            ? "关掉某个房间，就不再收到那边的动态，其他房间照常。"
            : "Turn a room off and it stops writing to you. The others carry on."
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
    /// Empty is how `AccountStore` stores "no name yet", so it has to behave
    /// like nil in every line below. `name.map` on "" would otherwise render a
    /// leading space and an orphaned verb — " 评论了你们的片段。"
    private static func named(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    // "朋友" was wrong twice over: it asserts a relationship the app never
    // established, and a room member with no name is not necessarily anyone's
    // friend. "有人" / "Someone" says only what is known.
    static func roomClipActivity(name: String?, day: Int) -> String {
        if lang == .chinese {
            return named(name).map { "\($0) 刚上传了第 \(day) 天的片段。" }
                ?? "有人刚上传了第 \(day) 天的片段。"
        }
        return named(name).map { "\($0) just added their Day \(day) clip." }
            ?? "Someone just added their Day \(day) clip."
    }
    static func roomCommentActivity(name: String?) -> String {
        if lang == .chinese {
            return named(name).map { "\($0) 评论了你们的片段。" } ?? "有人评论了你们的片段。"
        }
        return named(name).map { "\($0) commented on your shared film." }
            ?? "Someone commented on your shared film."
    }
    static func roomReactionActivity(name: String?) -> String {
        if lang == .chinese {
            return named(name).map { "\($0) 回应了你们的片段。" } ?? "有人回应了你们的片段。"
        }
        return named(name).map { "\($0) reacted to your shared film." }
            ?? "Someone reacted to your shared film."
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

    /// The word "moment", agreeing with a count. English needs this and Chinese
    /// doesn't, which is exactly how "Preview · 1 moments" got shipped: every
    /// caller wrote the plural in by hand and none of them had a story with one
    /// moment in it to look at.
    static func momentWord(_ count: Int) -> String {
        lang == .chinese ? "个瞬间" : (count == 1 ? "moment" : "moments")
    }

    static func storyLabel(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "一日影片" : "七日挑战" }
        return oneDay ? "1-day film" : "7-day challenge"
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

    /// Deleting a story and leaving a room are one menu item but two very
    /// different outcomes, and the difference is exactly what someone needs to
    /// know before they tap. Deleting takes the clips off this phone for good;
    /// leaving only takes the room off this phone — what you filmed stays in it
    /// for everyone else (`ChallengeStore.delete` clears locally and leaves the
    /// shared records alone).
    static func deleteStoryTitle(_ name: String) -> String {
        lang == .chinese ? "删除《\(name)》？" : "Delete “\(name)”?"
    }
    static func deleteStoryWarning(_ clipCount: Int) -> String {
        if lang == .chinese {
            return clipCount > 0
                ? "已经拍的 \(clipCount) 段视频会一起删掉，找不回来。"
                : "这个故事会从这台设备上删掉，找不回来。"
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
            ? "这台设备上就看不到这个房间了。你已经拍的片段还留在房间里，其他人照常能看。"
            : "The room disappears from this device. The clips you filmed stay in it — everyone else can still see them."
    }
    static var history: String { lang == .chinese ? "历史" : "HISTORY" }
    static var joining: String { lang == .chinese ? "加入中…" : "Joining…" }
    /// Shown while a poster tap is opening a shared room. The solo path is
    /// instant and needs nothing; this one is a network round trip, and without
    /// it the poster rack just sits there looking like the tap missed.
    static var creatingRoom: String { lang == .chinese ? "正在建房间…" : "Creating the room…" }
    static var couldNotCreateRoom: String {
        lang == .chinese ? "房间没建起来" : "Couldn't create the room"
    }
    /// On the header pill next to 新建, so the icon isn't the only clue.
    static var joinShort: String { lang == .chinese ? "加入" : "Join" }
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
    static var inviteHint: String {
        lang == .chinese ? "向朋友要 6 位邀请码。" : "Ask your friend for the 6-character code."
    }
    static var inviteCodeFormatHint: String {
        lang == .chinese
            ? "可以直接粘贴整段邀请文字。"
            : "Paste the whole invite if you have it."
    }
    /// Not "today's room": a room can be a seven-day story, and the button
    /// said otherwise on every one of them.
    static var joinRoomButton: String { lang == .chinese ? "加入房间" : "Join room" }

    static func oneDayProgress(
        _ recorded: Int,
        total: Int,
        secondsLabel: String
    ) -> String {
        lang == .chinese
            ? "\(recorded)/\(total) 个瞬间 · 每段 \(secondsLabel) · 24 小时影片"
            : "\(recorded)/\(total) \(secondsLabel) \(momentWord(total)) · 24-hour film"
    }

    // MARK: New challenge

    static func titlePrompt(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "我的一日故事…" : "我的七日目标…" }
        return oneDay ? "My 1-day story..." : "My 7-day goal..."
    }
    static var modeOneDay: String { lang == .chinese ? "一日" : "1-Day" }
    static var modeSevenDay: String { lang == .chinese ? "七日" : "7-Day" }
    static var clipLengthHeader: String { lang == .chinese ? "片段时长" : "CLIP LENGTH" }
    static var deleteTemplate: String { lang == .chinese ? "删除模板" : "Delete template" }
    static var editTemplate: String { lang == .chinese ? "编辑模板" : "Edit template" }
    static var buildYourOwn: String { lang == .chinese ? "自己搭一个" : "Build your own" }
    static var withFriends: String { lang == .chinese ? "和朋友一起" : "With friends" }
    static var createRoom: String { lang == .chinese ? "创建房间" : "Create room" }
    static func promptN(_ number: Int) -> String {
        lang == .chinese ? "第 \(number) 个拍摄标题" : "Capture title \(number)"
    }

    // MARK: Board

    static var friend: String { lang == .chinese ? "朋友" : "Friend" }
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
    static func momentCount(_ total: Int) -> String {
        lang == .chinese ? "24 小时，\(total) 个瞬间" : "\(total) \(momentWord(total)) in 24 hours"
    }
    static var record: String { lang == .chinese ? "拍摄" : "Record" }
    static func lockedSlot(oneDay: Bool, day: Int) -> String {
        if lang == .chinese { return oneDay ? "第 \(day) 个瞬间" : "第 \(day) 天" }
        return oneDay ? "Moment \(day)" : "Day \(day)"
    }

    // MARK: Record

    static var retake: String { lang == .chinese ? "重拍" : "Retake" }
    static var useClip: String { lang == .chinese ? "使用这段" : "Use clip" }
    /// The middle tab, and where the app opens: your stories.
    ///
    /// It was 计划 through 1.2, which named the *contents* of the screen rather
    /// than what the screen is for — and left the app with no tab that read as
    /// "my stuff". 计划 moved left onto the composer, which is the thing that
    /// actually makes a plan.
    static var surfacePlans: String { lang == .chinese ? "我的" : "Mine" }
    /// The left tab: making a new story. Called 计划 because that is what it
    /// produces; it was a wordless 36pt plus in the corner of the home screen
    /// until 1.3.
    static var surfaceCompose: String { lang == .chinese ? "计划" : "Plan" }
    static var surfaceCamera: String { lang == .chinese ? "拍摄" : "Camera" }
    static var freeformSlot: String { lang == .chinese ? "自由拍摄" : "Free-form" }
    static var fileToPlan: String { lang == .chinese ? "存入计划" : "File to a plan" }
    static var fileThisClipTo: String { lang == .chinese ? "把这段视频存入…" : "File this clip to…" }
    /// Filing one clip into several stories at once, new in 1.3.
    ///
    /// This was a `confirmationDialog` — a list of story names where tapping
    /// one filed the clip and closed the list. One take, one home. But a clip
    /// of the same afternoon belongs in your own story *and* in the room you
    /// share with the people who were there, and the old shape made that two
    /// takes of the same thing, or a re-film. Both stores copy the file
    /// (`ClipFileStore.storeClip`), so the clip can genuinely be in several
    /// stories at once rather than moved between them.
    static func fileToCount(_ count: Int) -> String {
        if lang == .chinese { return count <= 1 ? "存进去" : "存进 \(count) 个" }
        return count <= 1 ? "File it" : "File to \(count)"
    }
    /// Which slot the clip would land in, per row — so picking several is an
    /// informed choice rather than a guess about where each copy goes.
    static func landsIn(_ moment: String) -> String {
        lang == .chinese ? "放进「\(moment)」" : "Lands in \(moment)"
    }
    static func filedToCount(_ count: Int) -> String {
        if lang == .chinese { return "已存进 \(count) 个故事" }
        return count == 1 ? "Filed to 1 story" : "Filed to \(count) stories"
    }
    static var pickAtLeastOneStory: String {
        lang == .chinese ? "选一个地方放" : "Pick somewhere to put it"
    }
    static var makePlanFirst: String { lang == .chinese ? "先在计划页创建一个计划" : "Make a plan first in Plans" }
    static func filedTo(_ title: String) -> String {
        lang == .chinese ? "已存入「\(title)」" : "Filed to “\(title)”"
    }
    static var tapToStop: String { lang == .chinese ? "点按停止" : "Tap to stop" }
    static var orientationHeader: String { lang == .chinese ? "画幅" : "Orientation" }
    static var orientationPortrait: String { lang == .chinese ? "竖屏" : "Portrait" }
    static var orientationLandscape: String { lang == .chinese ? "横屏" : "Landscape" }
    static var orientationSquare: String { lang == .chinese ? "正方形" : "Square" }
    static var switchOrientation: String { lang == .chinese ? "切换画幅" : "Switch frame" }
    static var flipCamera: String { lang == .chinese ? "切换前后摄像头" : "Flip camera" }

    // The zoom values themselves ("0.5x") are formatted by `CameraZoom.label`
    // and are the same in both languages, so they are not copy.
    static var customZoom: String { lang == .chinese ? "自定义" : "Custom" }
    static var closeCustomZoom: String { lang == .chinese ? "收起自定义倍数" : "Close custom zoom" }
    static func zoomTo(_ value: String) -> String {
        lang == .chinese ? "缩放 \(value)" : "Zoom \(value)"
    }
    static var zoomSlider: String { lang == .chinese ? "缩放倍数" : "Zoom level" }

    /// The frame a clip was filmed in, named the way the picker names it — so
    /// "no landscape plan yet" and the row that would have created one agree.
    ///
    /// Taken as the orientation rather than a `landscape: Bool`: the bool had
    /// no third answer, and a square clip asking for "a portrait story" is a
    /// sentence that sends somebody to the wrong place.
    static func orientationName(_ orientation: Challenge.Orientation) -> String {
        switch orientation {
        case .portrait: lang == .chinese ? "竖屏" : "portrait"
        case .landscape: lang == .chinese ? "横屏" : "landscape"
        case .square: lang == .chinese ? "正方形" : "square"
        }
    }

    static func noMatchingPlan(_ orientation: Challenge.Orientation) -> String {
        let kind = orientationName(orientation)
        return lang == .chinese ? "没有\(kind)计划，先创建一个" : "No \(kind) plan yet — create one first"
    }

    // Drafts: what a clip does when there's nowhere to file it yet.
    static var saveAsDraft: String { lang == .chinese ? "先存起来" : "Keep it for now" }
    static var createStoryNow: String { lang == .chinese ? "现在就建个故事" : "Start a story now" }
    static var noPlaceYet: String { lang == .chinese ? "这段还没有地方放" : "Nowhere to put this yet" }
    static var keepClipQuestion: String { lang == .chinese ? "这段还没归档" : "This clip isn't filed yet" }
    static var keepClip: String { lang == .chinese ? "保留" : "Keep" }
    static var discardClip: String { lang == .chinese ? "丢弃" : "Discard" }
    /// Names where "keep" puts it. Without this the two buttons are a coin
    /// toss — nobody should have to guess whether "保留" means it goes
    /// somewhere findable or just stays on this screen.
    static var keepClipFootnote: String {
        lang == .chinese
            ? "「保留」会存进草稿，之后再决定放进哪个故事。「丢弃」之后这段就找不回来了。"
            : "Keep puts it in drafts to file later. Discard means it's gone."
    }
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
    /// Every slot in that story already holds a clip. Filing here would have to
    /// overwrite one, so it doesn't.
    static var storyIsFull: String {
        lang == .chinese ? "这个故事满了，没有空位" : "That story is full — no slot left."
    }
    /// No matching story for this clip's frame, from inside the drafts list —
    /// where "retake" isn't an option, so it says what would help instead.
    static func noPlaceForDraft(_ orientation: Challenge.Orientation) -> String {
        let kind = orientationName(orientation)
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
    /// Said separately from "camera not available", because the way out is
    /// different: iOS won't ask a second time, so retrying here can never work.
    static var cameraDeniedTitle: String {
        lang == .chinese ? "还没允许使用相机" : "Camera access is off"
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
    /// Spoken by the progress bars over the camera. There is no visible version
    /// of this — the bars themselves say it, and they only appear when the
    /// numbers in them are real.
    static func momentPosition(_ index: Int, of total: Int) -> String {
        lang == .chinese ? "第 \(index) 个瞬间，共 \(total) 个" : "Moment \(index) of \(total)"
    }
    static var addCaption: String { lang == .chinese ? "加一句字幕" : "add a caption" }
    static var writeOnMoment: String {
        lang == .chinese ? "给这个瞬间写点什么" : "Write on this moment"
    }

    // MARK: Clip preview

    static var rerecord: String { lang == .chinese ? "重录这一天" : "Re-record this day" }
    /// The same action as `rerecord`, for a chip sitting on top of the video
    /// where "Re-record this day" wraps to two lines and stops being a chip.
    static var rerecordShort: String { lang == .chinese ? "重拍" : "Retake" }
    /// The review screen's card of things you can do to one moment, and the
    /// button that gives the clip the whole display when you want it.
    static var thisMoment: String { lang == .chinese ? "这个瞬间" : "This moment" }
    static var addReaction: String { lang == .chinese ? "加个表情" : "Add a reaction" }
    /// The settings screen, which leads with who you are rather than with a
    /// list of switches.
    /// The settings sheet's own title. It was 「我」 until 1.3, when the story
    /// list took that name for the middle tab — two screens called 我 in one app
    /// is one too many, and of the two this is the one that is literally a list
    /// of settings.
    static var meTitle: String { lang == .chinese ? "设置" : "Settings" }
    static var tapToRename: String { lang == .chinese ? "点这里改名字" : "Tap to rename" }
    static var signedInWithApple: String {
        lang == .chinese ? "已用 Apple ID 登录" : "Signed in with Apple"
    }
    static var statStories: String { lang == .chinese ? "故事" : "Stories" }
    static var statMoments: String { lang == .chinese ? "瞬间" : "Moments" }
    /// Stories with every moment filmed. Deliberately not "films exported" —
    /// nothing tracks exports, and a number the app can't actually count is
    /// worse than one it can.
    static var statFinished: String { lang == .chinese ? "拍完了" : "Finished" }
    static var anyEmojiPlaceholder: String {
        lang == .chinese ? "或者打任意表情" : "Or type any emoji"
    }
    /// The chip that opens the caption editor. `addCaption` is the placeholder
    /// *inside* the editor, which is a sentence; this is a button, which isn't.
    static var captionAction: String { lang == .chinese ? "加字幕" : "Caption" }
    static var comments: String { lang == .chinese ? "评论" : "Comments" }
    static var firstComment: String {
        lang == .chinese ? "抢个沙发，说点什么吧。" : "Be the first to say something."
    }
    static var addComment: String { lang == .chinese ? "写评论…" : "Add a comment…" }

    // MARK: How you look

    /// Never "美颜" and never "beauty". Both words presume something is wrong
    /// with the face in the picture; the phone's camera is what was unkind.
    static var lookTitle: String { lang == .chinese ? "柔和一点" : "A gentler look" }
    /// The promise, said out loud on the screen where it matters: the file is
    /// never touched, so this is always undoable.
    static var lookFootnote: String {
        lang == .chinese
            ? "只改回看和成片。原片一直在，随时能关。"
            : "Changes playback and the film only. The recording is untouched."
    }
    /// The three dials. Named for what the camera got wrong, not for the Core
    /// Image filter underneath — nobody films thinking "my white point is off".
    static var lookExposure: String { lang == .chinese ? "亮度" : "Exposure" }
    static var lookTemperature: String { lang == .chinese ? "色温" : "Warmth" }
    static var lookContrast: String { lang == .chinese ? "对比" : "Contrast" }
    /// Puts all three dials back to centre.
    static var lookReset: String { lang == .chinese ? "复位" : "Reset" }
    static var lookHoldToCompare: String {
        lang == .chinese ? "按住看原片" : "Hold to see the original"
    }
    static var lookRemember: String { lang == .chinese ? "以后都这样看" : "Keep this from now on" }
    static var lookRememberFootnote: String {
        lang == .chinese
            ? "关掉的话，下次打开 app 就回到原样 —— 这次调的只算这次。"
            : "With this off, the app opens on “As shot” next time — today's choice is just for today."
    }

    // MARK: Final reel

    static var sequence: String { lang == .chinese ? "顺序" : "Sequence" }
    static var saving: String { lang == .chinese ? "保存中…" : "Saving…" }
    /// The film can't be rebuilt because the demo session it belonged to is
    /// over. Not an error the person did anything to cause, and not one
    /// "再试一次" can fix — so it says what happened and the retry button is the
    /// only thing on screen that still makes sense to press.
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
        lang == .chinese ? "需要相册权限才能保存视频。" : "Photos access is needed to save the video."
    }
    static var savedToPhotos: String { lang == .chinese ? "已保存到相册。" : "Saved to Photos." }
    static func saveFailed(_ error: String) -> String {
        lang == .chinese ? "保存视频失败：\(error)" : "Couldn't save video: \(error)"
    }
    static func titleCardSubtitleOneDay(_ recorded: Int, _ total: Int, secondsLabel: String) -> String {
        lang == .chinese
            ? "一日影片 · \(recorded)/\(total) 个瞬间 · 每段 \(secondsLabel)"
            : "1-day film · \(recorded)/\(total) \(secondsLabel) \(momentWord(total))"
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

    // MARK: Template library & covers

    static var saveToTemplateLibrary: String {
        lang == .chinese ? "存进我的模板库" : "Save to my template library"
    }
    static var saveToTemplateLibraryNote: String {
        lang == .chinese
            ? "下次开新故事，这套题目还在，直接选就行。"
            : "Next time you start a story, this set of prompts is still there."
    }
    static var templateCoverLabel: String {
        lang == .chinese ? "封面" : "COVER"
    }
    static var chooseCoverFromPhotos: String {
        lang == .chinese ? "从相册选一张" : "Choose from photos"
    }
    static var presetCoverHeading: String {
        lang == .chinese ? "选一个喜欢的场景" : "Choose a scene"
    }
    static var automaticCover: String {
        lang == .chinese ? "自动搭配" : "Automatic"
    }
    static var matchedCoverNote: String {
        lang == .chinese
            ? "不选也行，会按你写的题目配一张。"
            : "Or leave it — we'll match one to the prompts you wrote."
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
    static var errorNetwork: String {
        lang == .chinese
            ? "连不上 iCloud，检查一下网络再试。"
            : "Can't reach iCloud. Check your connection and try again."
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
    ///
    /// The only heading that list ever gets. It briefly alternated with a
    /// 「往前翻」 / "Earlier" variant for days holding nothing from today, but
    /// the hero is lifted *out* of the list — so the day you made a story was
    /// exactly the day the list renamed itself away from it. See `HomeStories`.
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
        lang == .chinese ? "\(total) 个瞬间" : "\(total) \(momentWord(total))"
    }
    /// "2s each" — the per-clip length on a template card.
    static func templateRuntime(count: Int, secondsLabel: String) -> String {
        lang == .chinese ? "每段 \(secondsLabel)" : "\(secondsLabel) each"
    }
    static var youLabel: String { lang == .chinese ? "你" : "You" }
    static var yoursLabel: String { lang == .chinese ? "自建" : "Yours" }
    /// One open moment, named on the home card so the story has a face on it.
    ///
    /// It says "还没拍" rather than "接下来" on purpose: the button beside it
    /// opens this moment because a card that small has to default to
    /// something, not because the day has to be filmed in this order. The
    /// story page, one tap away, offers all of them at once.
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
    static var customTemplateBlurb: String {
        lang == .chinese ? "你自己写的小脚本。" : "Your own little script."
    }
    static var noPrompts: String { lang == .chinese ? "无题目" : "No prompts" }

    // MARK: Story composer

    static var composerSetupStep: String { lang == .chinese ? "设置" : "Set it up" }
    static var newStoryQuestion: String {
        lang == .chinese ? "今天会是什么故事？" : "What will today's story be?"
    }
    /// The one-screen composer: the poster *is* the submit button, so the
    /// label above the grid has to say so — there is no 下一步 left to imply it.
    /// Shown under a caption the first time it is selected, then never again.
    /// Three gestures, in the order people reach for them.
    static var captionGestureHint: String {
        lang == .chinese
            ? "拖动移位置 · 两指捏大小 · 两指转角度"
            : "Drag to move · Pinch to resize · Twist to turn"
    }
    /// The ✕ on the selected caption's box, and the corner opposite it. Both
    /// are icon-only on screen, so these exist for VoiceOver and for the tests.
    static var deleteCaptionAction: String {
        lang == .chinese ? "删除字幕" : "Delete caption"
    }
    static var captionResizeHandle: String {
        lang == .chinese ? "缩放和旋转字幕" : "Resize and rotate caption"
    }
    /// What the four backing samples say. One character in Chinese, two letters
    /// in English — enough to show the colour on the backing, short enough that
    /// four samples fit a phone's width.
    static var captionPlateSample: String { lang == .chinese ? "字" : "Aa" }
    /// The samples are pictures, so these exist for VoiceOver and the tests.
    static func captionPlateName(_ style: CaptionSticker.Style) -> String {
        switch style {
        case .outline, .headline: lang == .chinese ? "不加底" : "No backing"
        case .band: lang == .chinese ? "半透明黑底" : "Dimmed backing"
        case .solid: lang == .chinese ? "纯黑底" : "Solid backing"
        case .light: lang == .chinese ? "白底" : "Light backing"
        }
    }
    /// On the button once a caption exists: it edits rather than adds.
    static var captionEditAction: String { lang == .chinese ? "改字幕" : "Edit caption" }
    /// Beside two other buttons on one row, so it is the short form.
    static var chatShort: String { lang == .chinese ? "聊天" : "Chat" }
    /// The seven dots under your avatar are colours, and a colour has no name
    /// worth saying out loud — numbered so VoiceOver can count them.
    static func avatarColourN(_ number: Int) -> String {
        lang == .chinese ? "头像颜色 \(number)" : "Avatar colour \(number)"
    }

    // MARK: - A story's cover

    /// On the home card when the button opens a day that isn't today, because
    /// today's is already filmed and an earlier one is missing.
    static func catchUpDayLabel(day: Int, moment: String) -> String {
        lang == .chinese ? "补第 \(day) 天 · \(moment)" : "Catch up day \(day) · \(moment)"
    }

    /// Next to the "needs photo access" line, so the dead end has a door.
    static var openSystemSettings: String {
        lang == .chinese ? "打开系统设置" : "Open Settings"
    }

    static var storyCoverTitle: String { lang == .chinese ? "换封面" : "Change cover" }
    /// First of the three sources, because a frame out of the day is the most
    /// honest cover a story can have.
    static var coverFromClips: String {
        lang == .chinese ? "从拍好的片段里选" : "From what you filmed"
    }
    static var coverFromPhotos: String {
        lang == .chinese ? "从相册选一张" : "Choose from photos"
    }
    static var coverFromLibrary: String { lang == .chinese ? "素材库" : "Cover library" }
    /// Confirms the lifted frame. The frame is on screen above it, so the word
    /// is 这张 and not "保存".
    static var useThisFrame: String { lang == .chinese ? "用这张" : "Use this one" }
    /// Back to the automatic cover — newest clip, then the poster. Named after
    /// what it does next, not after "reset".
    static var coverKeepFilming: String {
        lang == .chinese ? "改回跟着拍摄变" : "Follow what I film"
    }
    /// Under the evening reminder switch: when it will actually go off.
    static func nextReminderAt(_ when: String) -> String {
        lang == .chinese ? "下一次提醒：\(when)" : "Next reminder: \(when)"
    }
    /// Nothing unfilmed means nothing to nudge about — true, and worth saying,
    /// because it is otherwise identical to a broken switch.
    static var reminderNothingToNudge: String {
        lang == .chinese
            ? "今天没有要提醒的故事 —— 建一个就会排上"
            : "Nothing to remind you about yet — start a story and it'll queue up"
    }
    static var reminderBlocked: String {
        lang == .chinese
            ? "系统里关掉了通知，到「设置 › 通知 › 1Day」打开"
            : "Notifications are off in iOS Settings › Notifications › 1Day"
    }
    static var coverFrameFailed: String {
        lang == .chinese ? "这张图没读出来，换一张试试" : "Couldn't read that picture. Try another."
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
    /// The same two choices as `followPrompts` / `recordByTime`, shortened to
    /// share one row with 一日 and 七日. Four segments in a Chinese pill leave
    /// about three characters each.
    static var rackByTime: String {
        lang == .chinese ? "按时间" : "By time"
    }
    static var rackCustom: String {
        lang == .chinese ? "自己写" : "Your own"
    }
    /// The settings sheet behind a poster's gear, and the button that closes
    /// it by creating the story.
    static var storySettingsTitle: String {
        lang == .chinese ? "故事设置" : "Story settings"
    }
    static var startFilmingCTA: String {
        lang == .chinese ? "开始拍" : "Start filming"
    }
    /// The empty 自己写 rack: no saved prompt sets yet.
    static var noCustomTemplatesYet: String {
        lang == .chinese
            ? "还没有自己写的题目。写一组，它就留在这里。"
            : "No prompt sets of your own yet. Write one and it stays here."
    }
    static var customPromptsTitle: String {
        lang == .chinese ? "自己写题目" : "Write your own prompts"
    }
    /// On the entry card at the top of the composer, where it has to say what
    /// the screen behind it actually does — that one is 说说今天要干嘛 with a
    /// sentence in and prompts out, not a blank list to fill in yourself.
    static var customPromptsLead: String {
        lang == .chinese
            ? "说一句今天要干嘛，题目我来出"
            : "Say what today is for — I'll write the prompts"
    }
    static var timeOnlyCaptionNote: String {
        lang == .chinese
            ? "字幕由你自己在每段片子上填写，1Day 只负责保留拍摄时间。"
            : "You write the captions on each clip; 1Day just keeps the time."
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
    /// Shown before the room exists, so it has to say the room is empty. The
    /// composer used to show faces here instead, which read as "these people
    /// are already in" — nobody is, until an invite code gets used.
    static var roomExplainer: String {
        lang == .chinese
            ? "创建后房间里先只有你。把邀请码发出去，进来的人各自拍各自的瞬间，1Day 缝成一部影片。"
            : "At first the room is just you. Share the invite code — whoever joins films their own moments, and 1Day stitches them into one film."
    }
    /// Beside the room's own count, so "3/5" can mean the day and this can
    /// mean me. Only shown when the two differ.
    static var storyNameLabel: String { lang == .chinese ? "故事名字" : "Story name" }

    // MARK: Moments (composer)

    /// Carries the number, because it used to be hard-coded to seven and a
    /// three-moment story read "七个瞬间" over a list of three — a factual
    /// error the reader can see, on the page where they are deciding whether
    /// to trust the app with their day.
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
    static var guidedSubtitle: String {
        lang == .chinese
            ? "先写两个可能遇见的画面就够了。今天真正开始以后，随时还能增加或修改。"
            : "Start with two scenes you might encounter. Add or change them anytime once the day begins."
    }
    static var guidedNamePlaceholder: String {
        lang == .chinese ? "给这一天起个名字…" : "Name this day…"
    }
    /// Says what "就用这些" is still waiting for. A grey button whose reason
    /// lives off-screen is a dead end, and the name field scrolls away first.
    static func guidedFootnote(filled: Int, needsName: Bool) -> String {
        let enoughPrompts = filled >= 2
        switch (enoughPrompts, needsName) {
        case (false, true):
            return lang == .chinese
                ? "还差故事名字，和至少 2 个题目。"
                : "Still needs a name and at least 2 prompts."
        case (true, true):
            return lang == .chinese
                ? "题目够了。上面给这一天起个名字，就能保存。"
                : "Prompts are ready. Name the day up top and you can save."
        case (false, false):
            return lang == .chinese
                ? "已经写了 \(filled) 个，至少要 2 个。"
                : "\(filled) written; 2 is the minimum."
        case (true, false):
            return lang == .chinese
                ? "已经写了 \(filled) 个。2–7 个都可以，空白项不会加入故事。"
                : "\(filled) written. Use 2–7 prompts; blank rows won't be added to the story."
        }
    }
    /// Shown on the name card itself, where the fix is.
    static var storyNameNeeded: String {
        lang == .chinese ? "保存前得先起个名字。" : "A name is needed before saving."
    }
    // MARK: Prompts from one sentence

    static var intentHeading: String {
        lang == .chinese ? "说说今天要干嘛" : "What's today for?"
    }
    static var intentSubtitle: String {
        lang == .chinese
            ? "一句话就行。生成标题和题目，只填空白，不覆盖已有内容；每项都能改，也可以直接手写。"
            : "One sentence suggests a title and prompts. Only blanks are filled; existing text stays. Edit anything, or write your own."
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
    static var tapToFilm: String { lang == .chinese ? "点一下开拍" : "Tap to film" }
    /// Row labels. `clipLengthHeader` / `orientationHeader` are the older
    /// all-caps section headers and wrap awkwardly inside an `OptionRow`.
    static var clipLengthRow: String { lang == .chinese ? "片段时长" : "Clip length" }
    static var orientationRow: String { lang == .chinese ? "画面方向" : "Frame" }
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
    /// One heading over the three "what the app looks and reads like" rows.
    /// Each is a choice you make once, so they get one line apiece and the
    /// options live one screen down.
    static var displayAndLanguage: String {
        lang == .chinese ? "显示与语言" : "Display & Language"
    }
    static var inviteCodeLabel: String { lang == .chinese ? "邀请码" : "Invite code" }
    static var inviteCodeCopied: String { lang == .chinese ? "已复制" : "Copied" }
    static func previewTheFilm(_ count: Int) -> String {
        lang == .chinese ? "预览 · \(count) 个瞬间" : "Preview · \(count) \(momentWord(count))"
    }

    /// The story page: how far the day has got, and the words on the list of
    /// moments that are still yours to take.
    static func momentsFilmed(_ filmed: Int, total: Int) -> String {
        lang == .chinese ? "拍了 \(filmed)/\(total) 个瞬间" : "\(filmed) of \(total) filmed"
    }
    static var dayIsFull: String { lang == .chinese ? "这一天拍满了" : "The day is full" }
    /// The way into the film, on the one card the page allows itself — and
    /// only once there's nothing left to film.
    static var watchTheFilm: String { lang == .chinese ? "看成片" : "See the film" }
    static func filmFromMoments(_ clips: Int) -> String {
        lang == .chinese ? "\(clips) 个片段，缝成一部" : "\(clips) clips, one film"
    }
    /// The one row that's a suggestion. A question, because that's all it is —
    /// every other row does exactly the same thing when you tap it.
    static var startHere: String { lang == .chinese ? "先拍这个？" : "Start here?" }
    static var filmThisOne: String { lang == .chinese ? "开拍" : "Film it" }
    /// A moment a friend already filmed. The thumbnail plays their take; this
    /// row is how mine gets in.
    static var addYourTake: String { lang == .chinese ? "加上你的" : "Add yours" }
    static var watchThisMoment: String {
        lang == .chinese ? "看这个瞬间" : "Watch this moment"
    }
    static var retrySync: String { lang == .chinese ? "重新同步" : "Retry sync" }
    static var moreLabel: String { lang == .chinese ? "更多" : "More" }

    // MARK: Shared room

    /// The roster's caption. A room of one is worth saying out loud — an
    /// invite code nobody used looks exactly like a room full of friends until
    /// somebody counts the faces.
    static func peopleInRoom(_ count: Int) -> String {
        guard count > 1 else {
            return lang == .chinese ? "只有你在这个房间" : "Just you in this room"
        }
        return lang == .chinese ? "\(count) 人在这个房间" : "\(count) people in this room"
    }

    /// Whether anyone else showed up. Four sentences rather than a count,
    /// because "2 filmed" answers none of the four things a room is actually
    /// being asked: who's here, whether they've filmed, whether I have, and
    /// whether the day is waiting on me.
    ///
    /// - Parameters:
    ///   - overflow: people the line ran out of room to name.
    ///   - mineToo: I have filmed something as well.
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

    /// Who the room is waiting on. One line about people, never a row per
    /// moment: which moment they film is theirs to pick.
    static func roomWaitingOn(_ names: [String], overflow: Int) -> String {
        let who = nameList(names, overflow: overflow)
        return lang == .chinese ? "在等 \(who)" : "Waiting on \(who)"
    }

    /// Joins names the way each language does — Chinese enumerates with "、"
    /// and closes with "和", English with commas and "and". A capped list ends
    /// in a count rather than a name so one long name can't push the line off
    /// a 375pt screen.
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
    static var durationLabel: String { lang == .chinese ? "时长" : "Duration" }
    static var momentsLabel: String { lang == .chinese ? "瞬间" : "Moments" }
    static var peopleLabel: String { lang == .chinese ? "参与者" : "People" }
    static var rebuildFilm: String { lang == .chinese ? "重新生成" : "Rebuild film" }

    // MARK: Account

    static var account: String { lang == .chinese ? "账号" : "Account" }
    static var about: String { lang == .chinese ? "关于" : "About" }
    static var version: String { lang == .chinese ? "版本" : "Version" }
    static var privacyPolicy: String { lang == .chinese ? "隐私政策" : "Privacy Policy" }
    static var yourNamePlaceholder: String {
        lang == .chinese ? "朋友看到的名字" : "What friends see"
    }
    static var yourNameFootnote: String {
        lang == .chinese
            ? "共享房间里，你的片段会挂在这个名字下。改名只影响以后拍的。"
            : "This is the name on your clips in a shared room. Renaming affects clips from here on."
    }
    /// Apple only hands over a name on the very first sign-in. Without one,
    /// somebody has to be called something in a room full of friends.
    static var defaultMemberName: String { lang == .chinese ? "朋友" : "Friend" }
    static var notSignedIn: String {
        lang == .chinese ? "未登录（只有共享故事需要登录）" : "Not signed in — only shared stories need it"
    }
    /// The way back in. Until this existed, signing out was one-way from here:
    /// the only other sign-in gate is the one guarding a shared story.
    static var signIn: String { lang == .chinese ? "登录" : "Sign in" }
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
    /// Said out loud, because the alternative — a spinner that ends and a
    /// screen that looks finished — is the app claiming something it can't
    /// check. Naming what is still intact is what makes "try again" mean
    /// anything.
    static var deleteAccountFailedTitle: String {
        lang == .chinese ? "没有删干净" : "Not fully deleted"
    }
    static var deleteAccountFailedMessage: String {
        lang == .chinese
            ? "网络中断，云端还有一部分没删掉。你的故事和视频都还在这台设备上，没有动。连上网络后再试一次，会从断掉的地方接着删。"
            : "The connection dropped and some of your records are still in the cloud. Nothing on this device has been touched. Try again when you're back online and it will pick up where it stopped."
    }
    /// Replaces a departed creator's name on a room their friends still use.
    static var deletedMemberName: String {
        lang == .chinese ? "已注销的用户" : "A former member"
    }
}
