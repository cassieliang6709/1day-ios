import Foundation
import SwiftUI

/// A stable visual identity (color + initial) derived from a recorder's
/// name — used to tell whose clip is whose in a shared room, instead of the
/// old free-choice "sticker pack". `MemberChip` (ChallengeBoardView) shares
/// this same palette so a person's color matches everywhere in the app.
enum Identity {
    static let paletteUIColors: [UIColor] = [
        UIColor(Color.oneDayNavy), UIColor(Color.oneDayBlue), UIColor(Color.oneDayCyan),
        UIColor(Color.oneDaySky), .systemTeal, .systemBlue,
    ]

    static func uiColor(for name: String?) -> UIColor {
        guard let name, !name.isEmpty else { return UIColor(Color.oneDayBlue) }
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return paletteUIColors[sum % paletteUIColors.count]
    }

    static func tint(for name: String?) -> Color {
        Color(uiColor: uiColor(for: name))
    }

    /// Falls back to the app's brand mark when there's no one to identify
    /// (a solo challenge has no recorded author).
    static func initial(for name: String?) -> String {
        guard let name, let first = name.first else { return "1D" }
        return String(first).uppercased()
    }
}

struct Challenge: Codable, Identifiable {
    enum Mode: String, Codable, Hashable {
        case sevenDay
        case oneDay
    }

    enum ClipLength: String, Codable, CaseIterable, Identifiable {
        case tiny
        case story
        case scene

        var id: String { rawValue }

        var seconds: Double {
            switch self {
            case .tiny: 2
            case .story: 5
            case .scene: 10
            }
        }

        var secondsLabel: String {
            switch self {
            case .tiny: "2s"
            case .story: "5s"
            case .scene: "10s"
            }
        }

        var displayName: String {
            Strings.clipLengthName(self)
        }

        var caption: String {
            Strings.clipLengthCaption(self)
        }
    }

    let id: UUID
    var title: String
    var startDate: Date
    var cards: [DayCard]
    /// nil means an older saved challenge; treat it as the original 7-day flow.
    var mode: Mode? = nil
    /// nil means an older saved challenge; keep it on the original tiny clip.
    var clipLength: ClipLength? = nil
    var templateName: String? = nil
    var momentTitles: [String]? = nil

    /// nil = local ("just me") challenge. Non-nil = shared CloudKit room whose
    /// 6-char join code this is. Optional so old saved data still decodes.
    var roomCode: String? = nil
    /// Display name of whoever created the room (shown in the roster).
    var ownerName: String? = nil

    var isShared: Bool { roomCode != nil }
    var resolvedMode: Mode { mode ?? .sevenDay }
    var resolvedClipLength: ClipLength { clipLength ?? .tiny }
    var isOneDay: Bool { resolvedMode == .oneDay }

    /// 1-based index of "today" within the challenge (day 1 = startDate).
    /// Can exceed 7 once the week is over.
    var currentDay: Int {
        if isOneDay {
            let cal = Calendar.current
            let days = cal.dateComponents(
                [.day],
                from: cal.startOfDay(for: startDate),
                to: cal.startOfDay(for: .now)
            ).day ?? 0
            return days == 0 ? 1 : cards.count + 1
        }
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: startDate),
            to: cal.startOfDay(for: .now)
        ).day ?? 0
        return days + 1
    }

    var recordedCount: Int { cards.filter { $0.clipFileName != nil }.count }
    var isComplete: Bool { recordedCount == cards.count }

    var unitName: String { Strings.unitName(oneDay: isOneDay) }
    var unitNamePlural: String { Strings.unitNamePlural(oneDay: isOneDay) }
    var storyLabel: String { Strings.storyLabel(oneDay: isOneDay) }

    /// The prompt shown for a slot, localized. Stored `momentTitles` hold stable
    /// moment *keys* now, but legacy saved challenges/rooms may hold raw display
    /// strings — `MomentCatalog.localize` resolves all three (key, en, zh).
    func title(forSlot slot: Int) -> String {
        if let momentTitles, momentTitles.indices.contains(slot - 1) {
            return MomentCatalog.localize(momentTitles[slot - 1])
        }
        return Strings.dayN(slot)
    }

    func cardStatus(_ card: DayCard) -> DayCard.Status {
        if card.clipFileName != nil { return .done }
        if isOneDay {
            return currentDay > cards.count ? .missed : .today
        }
        return card.status(currentDay: currentDay)
    }
}

// MARK: - Moment catalog
//
// `AppLanguage`, `LocalizedText` and the `Strings` UI catalog live in
// Localization.swift.

/// The bilingual dictionary of every built-in moment prompt, keyed by a stable
/// language-independent key. Templates and saved challenges store these keys;
/// display resolves them here. Legacy data that stored raw display strings is
/// tolerated via `reverseIndex`.
enum MomentCatalog {
    struct Entry {
        let text: LocalizedText
        let icon: String
    }

    static let entries: [String: Entry] = [
        // Perfect Day
        "wake_up": .init(text: .init(en: "Wake up", zh: "起床"), icon: "sunrise.fill"),
        "coffee": .init(text: .init(en: "Coffee", zh: "咖啡"), icon: "cup.and.saucer.fill"),
        "get_ready": .init(text: .init(en: "Get ready", zh: "收拾出门"), icon: "tshirt.fill"),
        "out_the_door": .init(text: .init(en: "Out the door", zh: "出门"), icon: "door.left.hand.open"),
        "midday": .init(text: .init(en: "Midday", zh: "正午"), icon: "sun.max.fill"),
        "golden_hour": .init(text: .init(en: "Golden hour", zh: "傍晚的光"), icon: "sun.horizon.fill"),
        "wind_down": .init(text: .init(en: "Wind down", zh: "睡前放松"), icon: "moon.stars.fill"),
        // Soft Reset
        "messy_start": .init(text: .init(en: "Messy start", zh: "一团糟的开始"), icon: "scribble"),
        "clear_one_thing": .init(text: .init(en: "Clear one thing", zh: "先清一样东西"), icon: "checkmark.circle.fill"),
        "reset_corner": .init(text: .init(en: "Reset corner", zh: "整理一角"), icon: "arrow.triangle.2.circlepath"),
        "step_outside": .init(text: .init(en: "Step outside", zh: "出去走走"), icon: "wind"),
        "small_treat": .init(text: .init(en: "Small treat", zh: "小奖励"), icon: "cup.and.saucer.fill"),
        "cozy_detail": .init(text: .init(en: "Cozy detail", zh: "温柔的细节"), icon: "house.fill"),
        "after": .init(text: .init(en: "After", zh: "之后"), icon: "checkmark.seal.fill"),
        // Lock In
        "desk_setup": .init(text: .init(en: "Desk setup", zh: "布置桌面"), icon: "gearshape.fill"),
        "first_sprint": .init(text: .init(en: "First sprint", zh: "第一段冲刺"), icon: "bolt.fill"),
        "the_wall": .init(text: .init(en: "The wall", zh: "卡住了"), icon: "exclamationmark.triangle.fill"),
        "refuel": .init(text: .init(en: "Refuel", zh: "补充能量"), icon: "fork.knife"),
        "breakthrough": .init(text: .init(en: "Breakthrough", zh: "突破"), icon: "lightbulb.fill"),
        "almost_there": .init(text: .init(en: "Almost there", zh: "就快好了"), icon: "hourglass"),
        "shut_the_laptop": .init(text: .init(en: "Shut the laptop", zh: "合上电脑"), icon: "laptopcomputer"),
        // Main Character
        "morning_light": .init(text: .init(en: "Morning light", zh: "晨光"), icon: "sunrise.fill"),
        "fit_check": .init(text: .init(en: "Fit check", zh: "今日穿搭"), icon: "tshirt.fill"),
        "on_the_move": .init(text: .init(en: "On the move", zh: "在路上"), icon: "figure.walk"),
        "what_i_ate": .init(text: .init(en: "What I ate", zh: "吃了什么"), icon: "fork.knife"),
        "little_win": .init(text: .init(en: "Little win", zh: "小胜利"), icon: "trophy.fill"),
        "mirror_moment": .init(text: .init(en: "Mirror moment", zh: "镜子前"), icon: "person.crop.circle"),
        "night": .init(text: .init(en: "Night", zh: "夜晚"), icon: "moon.stars.fill"),
        // Cook With Me
        "ingredients": .init(text: .init(en: "Ingredients", zh: "备料"), icon: "basket.fill"),
        "prep": .init(text: .init(en: "Prep", zh: "切配"), icon: "fork.knife"),
        "the_sizzle": .init(text: .init(en: "The sizzle", zh: "下锅"), icon: "flame.fill"),
        "taste_test": .init(text: .init(en: "Taste test", zh: "尝味道"), icon: "hand.thumbsup.fill"),
        "plate_it": .init(text: .init(en: "Plate it", zh: "摆盘"), icon: "fork.knife.circle.fill"),
        "first_bite": .init(text: .init(en: "First bite", zh: "第一口"), icon: "face.smiling.fill"),
        "clean_up": .init(text: .init(en: "Clean up", zh: "收拾"), icon: "trash.fill"),
        // Out & About
        "meet_up": .init(text: .init(en: "Meet up", zh: "碰头"), icon: "person.2.fill"),
        "the_walk": .init(text: .init(en: "The walk", zh: "散步"), icon: "figure.walk"),
        "coffee_stop": .init(text: .init(en: "Coffee stop", zh: "喝杯咖啡"), icon: "cup.and.saucer.fill"),
        "best_moment": .init(text: .init(en: "Best moment", zh: "最好的瞬间"), icon: "star.fill"),
        "detour": .init(text: .init(en: "Detour", zh: "临时绕路"), icon: "map.fill"),
        "home": .init(text: .init(en: "Home", zh: "回家"), icon: "house.fill"),
        // Little Adventure
        "heading_out": .init(text: .init(en: "Heading out", zh: "出发"), icon: "figure.walk"),
        "first_stop": .init(text: .init(en: "First stop", zh: "第一站"), icon: "mappin.circle.fill"),
        "street_snack": .init(text: .init(en: "Street snack", zh: "街边小吃"), icon: "takeoutbag.and.cup.and.straw.fill"),
        "found_a_spot": .init(text: .init(en: "Found a spot", zh: "找到个地方"), icon: "mappin.and.ellipse"),
        "people_watching": .init(text: .init(en: "People watching", zh: "看人来人往"), icon: "person.2.fill"),
        "golden_light": .init(text: .init(en: "Golden light", zh: "傍晚的光"), icon: "sun.horizon.fill"),
        "back_home": .init(text: .init(en: "Back home", zh: "到家"), icon: "house.fill"),
        // Study Streak (moment-led rewrite)
        "first_sitdown": .init(text: .init(en: "First sit-down", zh: "第一次坐下"), icon: "chair.fill"),
        "getting_into_it": .init(text: .init(en: "Getting into it", zh: "进入状态了"), icon: "book.fill"),
        "refill_tank": .init(text: .init(en: "Refill the tank", zh: "给自己充电"), icon: "battery.100.bolt"),
        "look_back": .init(text: .init(en: "Look back", zh: "回头看看"), icon: "arrow.uturn.backward"),
        // 7 Days Moving
        "commit": .init(text: .init(en: "Commit", zh: "下定决心"), icon: "flag.fill"),
        "sweat": .init(text: .init(en: "Sweat", zh: "流汗"), icon: "figure.run"),
        "sore": .init(text: .init(en: "Sore", zh: "酸痛"), icon: "bandage.fill"),
        "push": .init(text: .init(en: "Push", zh: "逼自己一把"), icon: "bolt.heart.fill"),
        "flow": .init(text: .init(en: "Flow", zh: "顺起来了"), icon: "figure.cooldown"),
        "strong": .init(text: .init(en: "Strong", zh: "变强了"), icon: "figure.strengthtraining.traditional"),
        "proof": .init(text: .init(en: "Proof", zh: "证明"), icon: "checkmark.seal.fill"),
        // Morning Person
        "the_6am_test": .init(text: .init(en: "The 6am test", zh: "六点起床挑战"), icon: "alarm.fill"),
        "make_the_bed": .init(text: .init(en: "Make the bed", zh: "叠被子"), icon: "bed.double.fill"),
        "move_your_body": .init(text: .init(en: "Move your body", zh: "动一动"), icon: "figure.walk"),
        "no_phone": .init(text: .init(en: "No phone", zh: "不看手机"), icon: "hand.raised.slash.fill"),
        "real_breakfast": .init(text: .init(en: "Real breakfast", zh: "好好吃早饭"), icon: "fork.knife"),
        "sunlight": .init(text: .init(en: "Sunlight", zh: "晒太阳"), icon: "sun.max.fill"),
        "your_best_morning": .init(text: .init(en: "Your best morning", zh: "最好的早晨"), icon: "sunrise.fill"),
        // Study Streak
        "plan": .init(text: .init(en: "Plan", zh: "计划"), icon: "calendar"),
        "deep_work": .init(text: .init(en: "Deep work", zh: "专注攻坚"), icon: "book.fill"),
        "review": .init(text: .init(en: "Review", zh: "复习"), icon: "arrow.triangle.2.circlepath"),
        "hard_topic": .init(text: .init(en: "Hard topic", zh: "硬骨头"), icon: "brain.head.profile"),
        "practice": .init(text: .init(en: "Practice", zh: "刷题"), icon: "pencil"),
        "mock_test": .init(text: .init(en: "Mock test", zh: "模考"), icon: "checklist"),
        "recap": .init(text: .init(en: "Recap", zh: "回顾"), icon: "note.text"),
        // Eat Well
        "fridge_check": .init(text: .init(en: "Fridge check", zh: "看看冰箱"), icon: "refrigerator.fill"),
        "cook_one_meal": .init(text: .init(en: "Cook one meal", zh: "做一顿饭"), icon: "flame.fill"),
        "try_something_new": .init(text: .init(en: "Try something new", zh: "试点新的"), icon: "sparkles"),
        "meal_prep": .init(text: .init(en: "Meal prep", zh: "备餐"), icon: "takeoutbag.and.cup.and.straw.fill"),
        "no_takeout": .init(text: .init(en: "No takeout", zh: "不点外卖"), icon: "xmark.circle.fill"),
        "share_a_meal": .init(text: .init(en: "Share a meal", zh: "一起吃"), icon: "person.2.fill"),
        "favorite_dish": .init(text: .init(en: "Favorite dish", zh: "拿手菜"), icon: "heart.fill"),
        // Calm Week
        "one_deep_breath": .init(text: .init(en: "One deep breath", zh: "深呼吸"), icon: "wind"),
        "five_min_sit": .init(text: .init(en: "5-min sit", zh: "静坐五分钟"), icon: "figure.mind.and.body"),
        "walk_no_phone": .init(text: .init(en: "Walk, no phone", zh: "散步不带手机"), icon: "figure.walk"),
        "journal": .init(text: .init(en: "Journal", zh: "写日记"), icon: "book.closed.fill"),
        "stretch": .init(text: .init(en: "Stretch", zh: "拉伸"), icon: "figure.flexibility"),
        "digital_sunset": .init(text: .init(en: "Digital sunset", zh: "睡前断网"), icon: "moon.zzz.fill"),
        "stillness": .init(text: .init(en: "Stillness", zh: "安静下来"), icon: "leaf.fill"),
        // Make Something
        "blank_page": .init(text: .init(en: "Blank page", zh: "空白页"), icon: "doc.fill"),
        "first_mark": .init(text: .init(en: "First mark", zh: "第一笔"), icon: "pencil.tip"),
        "ugly_middle": .init(text: .init(en: "Ugly middle", zh: "丑陋的中途"), icon: "scribble.variable"),
        "keep_going": .init(text: .init(en: "Keep going", zh: "继续"), icon: "arrow.forward.circle.fill"),
        "detail": .init(text: .init(en: "Detail", zh: "细节"), icon: "magnifyingglass"),
        "almost": .init(text: .init(en: "Almost", zh: "快好了"), icon: "hourglass"),
        "finished_piece": .init(text: .init(en: "Finished piece", zh: "完成的作品"), icon: "paintpalette.fill"),
    ]

    /// Resolve a stored token — a catalog key, or a legacy en/zh display string —
    /// to the active language, falling back to the token itself.
    static func localize(_ token: String, _ lang: AppLanguage = .effective) -> String {
        if let e = entries[token] { return e.text.resolved(lang) }
        if let key = reverseIndex[token] { return entries[key]!.text.resolved(lang) }
        return token
    }

    /// The stable key for a display string, if any — used to migrate legacy
    /// custom templates that stored English prompts into keys.
    static func key(forDisplay token: String) -> String? {
        entries[token] != nil ? token : reverseIndex[token]
    }

    /// SF Symbol for a token (key or display string).
    static func icon(for token: String?) -> String {
        guard let token else { return "video.circle.fill" }
        if let e = entries[token] { return e.icon }
        if let key = reverseIndex[token] { return entries[key]!.icon }
        return "video.circle.fill"
    }

    /// Every localized string (en + zh) → key, so a stored display string still
    /// resolves after the switch to key-based storage.
    private static let reverseIndex: [String: String] = {
        var idx: [String: String] = [:]
        for (key, e) in entries {
            idx[e.text.en] = key
            idx[e.text.zh] = key
        }
        return idx
    }()
}

/// A named, ordered list of moment prompts. Built-in templates ship with the
/// app; custom ones are user-assembled in `BuildTemplateView` and persisted
/// by `ChallengeStore`. Names and moments are bilingual: built-ins carry both
/// languages, moments are stored as stable keys into `MomentCatalog`.
struct ChallengeTemplate: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var emoji: String
    /// Bilingual name. Custom templates set both sides to the user's typed name.
    var name: LocalizedText
    /// Stable moment keys into `MomentCatalog` (custom templates pick from the
    /// same pool, so their moments are keyed too).
    var momentKeys: [String]?
    /// Built-ins are identified by name (stable across app versions); custom
    /// ones by their generated id, since a user could name two the same.
    var isCustom: Bool = false

    init(id: UUID = UUID(), emoji: String, name: LocalizedText,
         momentKeys: [String]?, isCustom: Bool = false) {
        self.id = id
        self.emoji = emoji
        self.name = name
        self.momentKeys = momentKeys
        self.isCustom = isCustom
    }

    /// Name in the active language.
    var displayName: String { name.resolved() }
    /// Language-stable string for deriving a consistent accent color.
    var identityKey: String { name.en }
    /// Localized moment prompts — for the card's count and any list display.
    var momentTitles: [String]? { momentKeys?.map { MomentCatalog.localize($0) } }

    static func == (lhs: ChallengeTemplate, rhs: ChallengeTemplate) -> Bool {
        lhs.isCustom ? lhs.id == rhs.id : lhs.name.en == rhs.name.en
    }

    static let oneDayBuiltins: [ChallengeTemplate] = [
        .init(emoji: "🌅", name: .init(en: "Perfect Day", zh: "完美的一天"),
              momentKeys: ["wake_up", "coffee", "get_ready", "out_the_door", "midday", "golden_hour", "wind_down"]),
        .init(emoji: "🌿", name: .init(en: "Soft Reset", zh: "慢慢重启"),
              momentKeys: ["messy_start", "clear_one_thing", "reset_corner", "step_outside", "small_treat", "cozy_detail", "after"]),
        .init(emoji: "✍️", name: .init(en: "Lock In", zh: "进入状态"),
              momentKeys: ["desk_setup", "first_sprint", "the_wall", "refuel", "breakthrough", "almost_there", "shut_the_laptop"]),
        .init(emoji: "✨", name: .init(en: "Main Character", zh: "我的主角日"),
              momentKeys: ["morning_light", "fit_check", "on_the_move", "what_i_ate", "little_win", "mirror_moment", "night"]),
        .init(emoji: "🍳", name: .init(en: "Cook With Me", zh: "和我做饭"),
              momentKeys: ["ingredients", "prep", "the_sizzle", "taste_test", "plate_it", "first_bite", "clean_up"]),
        .init(emoji: "🧭", name: .init(en: "Little Adventure", zh: "出门冒险"),
              momentKeys: ["heading_out", "first_stop", "street_snack", "found_a_spot", "people_watching", "golden_light", "back_home"]),
    ]

    static let sevenDayBuiltins: [ChallengeTemplate] = [
        .init(emoji: "💪", name: .init(en: "7 Days Moving", zh: "动起来的一周"),
              momentKeys: ["commit", "sweat", "sore", "push", "flow", "strong", "proof"]),
        .init(emoji: "🌅", name: .init(en: "Morning Person", zh: "早起的人"),
              momentKeys: ["the_6am_test", "make_the_bed", "move_your_body", "no_phone", "real_breakfast", "sunlight", "your_best_morning"]),
        .init(emoji: "📚", name: .init(en: "Study Streak", zh: "学习打卡"),
              momentKeys: ["first_sitdown", "getting_into_it", "the_wall", "little_win", "refill_tank", "almost_there", "look_back"]),
        .init(emoji: "🥗", name: .init(en: "Eat Well", zh: "好好吃饭"),
              momentKeys: ["fridge_check", "cook_one_meal", "try_something_new", "meal_prep", "no_takeout", "share_a_meal", "favorite_dish"]),
        .init(emoji: "🧘", name: .init(en: "Calm Week", zh: "平静一周"),
              momentKeys: ["one_deep_breath", "five_min_sit", "walk_no_phone", "journal", "stretch", "digital_sunset", "stillness"]),
        .init(emoji: "🎨", name: .init(en: "Make Something", zh: "做点东西"),
              momentKeys: ["blank_page", "first_mark", "ugly_middle", "keep_going", "detail", "almost", "finished_piece"]),
    ]

    /// Every moment key across the built-in 1-day templates, deduplicated and in
    /// first-seen order — the pool `BuildTemplateView` picks from.
    static let promptPool: [String] = {
        var seen = Set<String>()
        var pool: [String] = []
        for template in oneDayBuiltins {
            for key in template.momentKeys ?? [] where seen.insert(key).inserted {
                pool.append(key)
            }
        }
        return pool
    }()

    /// SF Symbol for a slot, given its moment key (or a legacy display string).
    static func icon(forPrompt prompt: String?) -> String {
        MomentCatalog.icon(for: prompt)
    }

    // MARK: Codable (back-compat with pre-bilingual saved custom templates)

    enum CodingKeys: String, CodingKey {
        case id, emoji, name, momentKeys, momentTitles, isCustom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? "🎬"
        isCustom = (try? c.decode(Bool.self, forKey: .isCustom)) ?? false
        // name: new bilingual object, or a legacy plain string.
        if let loc = try? c.decode(LocalizedText.self, forKey: .name) {
            name = loc
        } else {
            let raw = (try? c.decode(String.self, forKey: .name)) ?? ""
            name = LocalizedText(en: raw, zh: raw)
        }
        // moments: new keys, or legacy display strings migrated to keys.
        if let keys = try? c.decodeIfPresent([String].self, forKey: .momentKeys) {
            momentKeys = keys
        } else if let legacy = try? c.decodeIfPresent([String].self, forKey: .momentTitles) {
            momentKeys = legacy.map { MomentCatalog.key(forDisplay: $0) ?? $0 }
        } else {
            momentKeys = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(emoji, forKey: .emoji)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(momentKeys, forKey: .momentKeys)
        try c.encode(isCustom, forKey: .isCustom)
    }
}

/// A recorded clip labeled with its challenge day — the stitcher's input.
/// In a shared room a single day can hold several clips (one per friend), so
/// `id` is unique rather than the day number.
struct DayClip: Identifiable {
    let id: String
    let day: Int
    let url: URL
    var authorName: String?
    var label: String?
    var overlayText: String?
    var recordedAt: Date?
    /// Emoji to float onto this clip in the final film (from its reactions).
    var emoji: [String]

    init(
        day: Int,
        url: URL,
        authorName: String? = nil,
        label: String? = nil,
        overlayText: String? = nil,
        recordedAt: Date? = nil,
        emoji: [String] = [],
        key: String? = nil
    ) {
        self.day = day
        self.url = url
        self.authorName = authorName
        self.label = label
        self.overlayText = overlayText
        self.recordedAt = recordedAt
        self.emoji = emoji
        self.id = key ?? "day\(day)"
    }
}

/// A single emoji left on a clip. One per (author, emoji) pair, so tapping the
/// same emoji again toggles it off. Local-first; mirrored to a room when shared.
struct ClipReaction: Codable, Identifiable, Equatable {
    var emoji: String
    var authorID: String
    var authorName: String
    var createdAt: Date = .now

    /// Stable across the same person's same emoji — drives toggle + dedupe.
    var id: String { "\(authorID)|\(emoji)" }

    /// The fixed palette offered in the reaction bar.
    static let palette = ["❤️", "🔥", "😂", "👏", "🥹", "✨"]
}

/// A short text note someone left on a clip. A "reply" is just another comment —
/// no threading in v1, which keeps the sync + UI shippable.
struct ClipComment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var authorID: String
    var authorName: String
    var createdAt: Date = .now
}

struct DayCard: Codable, Identifiable {
    let day: Int
    var clipFileName: String?
    var recordedAt: Date?
    var overlayText: String?
    var reactions: [ClipReaction] = []
    var comments: [ClipComment] = []

    var id: Int { day }

    init(
        day: Int,
        clipFileName: String? = nil,
        recordedAt: Date? = nil,
        overlayText: String? = nil,
        reactions: [ClipReaction] = [],
        comments: [ClipComment] = []
    ) {
        self.day = day
        self.clipFileName = clipFileName
        self.recordedAt = recordedAt
        self.overlayText = overlayText
        self.reactions = reactions
        self.comments = comments
    }

    enum CodingKeys: String, CodingKey {
        case day, clipFileName, recordedAt, overlayText, reactions, comments
    }

    // Custom decode: synthesized Codable would throw on the reactions/comments
    // keys being absent in pre-existing saved challenges. Default them instead
    // so an app update never wipes someone's in-progress challenge.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(Int.self, forKey: .day)
        clipFileName = try c.decodeIfPresent(String.self, forKey: .clipFileName)
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt)
        overlayText = try c.decodeIfPresent(String.self, forKey: .overlayText)
        reactions = try c.decodeIfPresent([ClipReaction].self, forKey: .reactions) ?? []
        comments = try c.decodeIfPresent([ClipComment].self, forKey: .comments) ?? []
    }

    enum Status: Equatable {
        case done      // clip recorded
        case today     // it's this day, no clip yet
        case missed    // day passed without a clip (still recordable, late)
        case locked    // future day
    }

    func status(currentDay: Int) -> Status {
        if clipFileName != nil { return .done }
        if day == currentDay { return .today }
        if day < currentDay { return .missed }
        return .locked
    }
}
