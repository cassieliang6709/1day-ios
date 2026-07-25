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
            ? "“跟随系统”会使用设备语言。模板、moment 和菜单会立即切换。"
            : "“System” follows your device language. Templates, moments and menus switch instantly."
    }

    // MARK: Models

    static func dayN(_ day: Int) -> String {
        lang == .chinese ? "第 \(day) 天" : "Day \(day)"
    }

    static func unitName(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "个 moment" : "天" }
        return oneDay ? "moment" : "day"
    }

    static func unitNamePlural(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "个 moment" : "天" }
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
        lang == .chinese ? "7 个瞬间，一支小 vlog。" : "7 moments. One tiny vlog."
    }
    static var haveInviteCode: String { lang == .chinese ? "我有邀请码" : "I have an invite code" }
    static var firstRunPrompt: String {
        lang == .chinese ? "想记录什么样的一天？" : "What kind of day do you want to remember?"
    }
    static var makeMyOwn: String { lang == .chinese ? "自己定制" : "Make my own" }
    static func momentsCount(_ count: Int) -> String {
        lang == .chinese ? "\(count) 个瞬间" : "\(count) moments"
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
    static func oneDayProgress(_ recorded: Int, secondsLabel: String) -> String {
        lang == .chinese
            ? "\(recorded)/7 个 \(secondsLabel) moment · 24 小时影片"
            : "\(recorded)/7 \(secondsLabel) moments · 24-hour film"
    }
    static func friendsRange(_ count: Int, _ range: String) -> String {
        lang == .chinese ? "\(count) 位朋友 · \(range)" : "\(count) friends · \(range)"
    }
    static func endedRecorded(_ recorded: Int) -> String {
        lang == .chinese ? "已结束 · 已录 \(recorded)/7" : "Ended · \(recorded)/7 recorded"
    }
    static func dayOfRange(_ day: Int, _ range: String) -> String {
        lang == .chinese ? "第 \(day) 天，共 7 天 · \(range)" : "Day \(day) of 7 · \(range)"
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
    static func headerSubtitle(oneDay: Bool, secondsLabel: String) -> String {
        if lang == .chinese {
            return oneDay
                ? "7 个 moment，每个 \(secondsLabel)。今晚剪成一部小短片。"
                : "每天 \(secondsLabel)，七天后合成一部片子。"
        }
        return oneDay
            ? "7 moments, \(secondsLabel) each. One tiny film tonight."
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
            ? "\(count) 个 moment，每个 \(secondsLabel)"
            : "\(count) moments, \(secondsLabel) each"
    }
    static var selectedLabel: String { lang == .chinese ? "已选" : "Selected" }
    static var tapToSelect: String {
        lang == .chinese ? "点一下选这个脚本" : "Tap to select this script"
    }
    static var deleteTemplate: String { lang == .chinese ? "删除模板" : "Delete template" }
    static var buildYourOwn: String { lang == .chinese ? "自己搭一个" : "Build your own" }
    static var pickYourPrompts: String {
        lang == .chinese ? "挑你自己的 moment" : "Pick your own prompts"
    }
    static var whosIn: String { lang == .chinese ? "谁参与" : "WHO'S IN" }
    static var justMe: String { lang == .chinese ? "只有我" : "Just me" }
    static var privateWeek: String { lang == .chinese ? "私密的一周" : "A private week" }
    static var withFriends: String { lang == .chinese ? "和朋友一起" : "With friends" }
    static var roomInvite: String { lang == .chinese ? "房间 + 邀请码" : "Room + invite code" }
    static var createRoom: String { lang == .chinese ? "创建房间" : "Create room" }
    static var startMoment1: String { lang == .chinese ? "开始 Moment 1" : "Start Moment 1" }
    static var startDay1: String { lang == .chinese ? "开始第 1 天" : "Start Day 1" }

    // MARK: Board

    static var fillDemoClips: String { lang == .chinese ? "填充示例片段" : "Fill with demo clips" }
    static func createFilm(oneDay: Bool) -> String {
        if lang == .chinese { return oneDay ? "生成一日影片" : "生成每周影片" }
        return oneDay ? "Create 1-day film" : "Create weekly film"
    }
    static func previewFilm(_ recorded: Int, _ total: Int, unitPlural: String) -> String {
        lang == .chinese
            ? "预览影片 · \(recorded)/\(total) \(unitPlural)"
            : "Preview film · \(recorded)/\(total) \(unitPlural)"
    }
    static func membersInRoom(_ count: Int) -> String {
        lang == .chinese ? "房间里有 \(count) 人" : "\(count) in this room"
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
    static func recordedProgress(_ recorded: Int, secondsLabel: String, unitPlural: String) -> String {
        lang == .chinese
            ? "7 \(unitPlural)中已录 \(recorded) 段（\(secondsLabel)）"
            : "\(recorded) of 7 \(secondsLabel) \(unitPlural) recorded"
    }
    static var oneDayComplete: String { lang == .chinese ? "一日影片完成" : "1-day film complete" }
    static var sevenMoments: String {
        lang == .chinese ? "24 小时，7 个瞬间" : "7 moments in 24 hours"
    }
    static var weekComplete: String { lang == .chinese ? "本周完成" : "Week complete" }
    static func dayOf(_ day: Int) -> String {
        lang == .chinese ? "第 \(day) 天，共 7 天" : "Day \(day) of 7"
    }
    static var record: String { lang == .chinese ? "拍摄" : "Record" }
    static var catchUp: String { lang == .chinese ? "补拍" : "Catch up" }
    static func lockedSlot(oneDay: Bool, day: Int) -> String {
        if lang == .chinese { return oneDay ? "第 \(day) 个 moment" : "第 \(day) 天" }
        return oneDay ? "Moment \(day)" : "Day \(day)"
    }

    // MARK: Record

    static var retake: String { lang == .chinese ? "重拍" : "Retake" }
    static var useClip: String { lang == .chinese ? "使用这段" : "Use clip" }
    static var surfacePlans: String { lang == .chinese ? "计划" : "plans" }
    static var surfaceCamera: String { lang == .chinese ? "拍摄" : "camera" }
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
    static func noMatchingPlan(landscape: Bool) -> String {
        let kind = landscape
            ? (lang == .chinese ? "横屏" : "landscape")
            : (lang == .chinese ? "竖屏" : "portrait")
        return lang == .chinese ? "没有\(kind)计划，先创建一个" : "No \(kind) plan yet — create one first"
    }
    static var cameraUnavailable: String { lang == .chinese ? "相机不可用" : "Camera not available" }
    static func useDemoClip(_ title: String) -> String {
        lang == .chinese ? "为「\(title)」使用示例片段" : "Use demo clip for \(title)"
    }
    static var openingCamera: String { lang == .chinese ? "正在打开相机" : "Opening camera" }
    static func captureState(recording: Bool, secondsLabel: String) -> String {
        if lang == .chinese { return recording ? "\(secondsLabel) 拍摄中" : "轻点拍摄" }
        return recording ? "\(secondsLabel) capture" : "tap to capture"
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
        lang == .chinese ? "使用 AVFoundation 在设备端渲染" : "Rendered on-device with AVFoundation"
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
            ? "一日影片 · \(recorded)/\(total) 个 \(secondsLabel) moment"
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

    /// DEBUG-only demo overlay caption.
    static var demoFirstProof: String { lang == .chinese ? "第一个小证据" : "first little proof" }
}
