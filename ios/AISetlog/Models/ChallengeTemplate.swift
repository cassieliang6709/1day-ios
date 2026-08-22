import Foundation

/// A named, ordered list of moment prompts. Built-in templates ship with the
/// app; custom ones are user-assembled in `BuildTemplateView` and persisted
/// by `ChallengeStore`. Names and moments are bilingual: built-ins carry both
/// languages, moments are stored as stable keys into `MomentCatalog`.
struct ChallengeTemplate: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    /// Legacy: templates used to be identified by an emoji. Kept so saved
    /// custom templates still decode, but nothing renders it any more.
    var emoji: String
    /// SF Symbol shown on the template card. Native icons sit inside the app's
    /// type and colour system in a way emoji never can — an emoji is somebody
    /// else's illustration at somebody else's weight.
    var symbol: String?
    /// Bilingual name. Custom templates set both sides to the user's typed name.
    var name: LocalizedText
    /// Stable moment keys into `MomentCatalog` (custom templates pick from the
    /// same pool, so their moments are keyed too).
    var momentKeys: [String]?
    /// One emotional line under the name — what the day is *supposed to feel
    /// like*. Shown on the template card so picking a story reads like picking
    /// a mood, not a task list. Custom templates leave it nil.
    var blurb: LocalizedText?
    /// Built-ins are identified by name (stable across app versions); custom
    /// ones by their generated id, since a user could name two the same.
    var isCustom: Bool = false

    init(id: UUID = UUID(), emoji: String = "", symbol: String? = nil,
         name: LocalizedText, momentKeys: [String]?,
         blurb: LocalizedText? = nil, isCustom: Bool = false) {
        self.id = id
        self.emoji = emoji
        self.symbol = symbol
        self.name = name
        self.momentKeys = momentKeys
        self.blurb = blurb
        self.isCustom = isCustom
    }

    /// Name in the active language.
    var displayName: String { name.resolved() }
    /// The card's icon, with a fallback for templates saved before symbols.
    var displaySymbol: String { symbol ?? "wand.and.stars" }
    /// Language-stable string for deriving a consistent accent color.
    var identityKey: String { name.en }
    /// Built-in poster art. Custom templates use the shared custom-story art
    /// at the presentation layer because their names are user-authored.
    var coverAssetName: String? {
        guard !isCustom else { return nil }
        return switch name.en {
        case "Perfect Day": "TemplatePerfectDay"
        case "Soft Reset": "TemplateSoftReset"
        case "Lock In": "TemplateLockIn"
        case "Main Character": "TemplateMainCharacter"
        case "Cook With Me": "TemplateCookWithMe"
        case "Little Adventure": "TemplateLittleAdventure"
        case "7 Days Moving": "TemplateSevenDaysMoving"
        case "Morning Person": "TemplateMorningPerson"
        case "Study Streak": "TemplateStudyStreak"
        case "Eat Well": "TemplateEatWell"
        case "Calm Week": "TemplateCalmWeek"
        case "Make Something": "TemplateMakeSomething"
        default: nil
        }
    }
    /// Localized moment prompts — for the card's count and any list display.
    var momentTitles: [String]? { momentKeys?.map { MomentCatalog.localize($0) } }

    static func == (lhs: ChallengeTemplate, rhs: ChallengeTemplate) -> Bool {
        lhs.isCustom ? lhs.id == rhs.id : lhs.name.en == rhs.name.en
    }

    static let oneDayBuiltins: [ChallengeTemplate] = [
        .init(symbol: "sun.max.fill", name: .init(en: "Perfect Day", zh: "完美的一天"),
              momentKeys: ["wake_up", "coffee", "get_ready", "out_the_door", "midday", "golden_hour", "wind_down"],
              blurb: .init(en: "The day you'd happily live twice.", zh: "愿意再过一遍的一天。")),
        .init(symbol: "leaf.fill", name: .init(en: "Soft Reset", zh: "慢慢重启"),
              momentKeys: ["messy_start", "clear_one_thing", "reset_corner", "step_outside", "small_treat", "cozy_detail", "after"],
              blurb: .init(en: "A quiet day to begin again.", zh: "安静地重新开始。")),
        .init(symbol: "scope", name: .init(en: "Lock In", zh: "进入状态"),
              momentKeys: ["desk_setup", "first_sprint", "the_wall", "refuel", "breakthrough", "almost_there", "shut_the_laptop"],
              blurb: .init(en: "Focus. Everything else waits.", zh: "先专注，其他都等等。")),
        .init(symbol: "sparkles", name: .init(en: "Main Character", zh: "我的主角日"),
              momentKeys: ["morning_light", "fit_check", "on_the_move", "what_i_ate", "little_win", "mirror_moment", "night"],
              blurb: .init(en: "Today the camera follows you.", zh: "今天，镜头跟着你走。")),
        .init(symbol: "flame.fill", name: .init(en: "Cook With Me", zh: "和我做饭"),
              momentKeys: ["ingredients", "prep", "the_sizzle", "taste_test", "plate_it", "first_bite", "clean_up"],
              blurb: .init(en: "Raw ingredients to the first bite.", zh: "从备料，到第一口。")),
        .init(symbol: "map.fill", name: .init(en: "Little Adventure", zh: "出门冒险"),
              momentKeys: ["heading_out", "first_stop", "street_snack", "found_a_spot", "people_watching", "golden_light", "back_home"],
              blurb: .init(en: "Leave the house. See what happens.", zh: "出门，看看会遇到什么。")),
    ]

    static let sevenDayBuiltins: [ChallengeTemplate] = [
        .init(symbol: "figure.run", name: .init(en: "7 Days Moving", zh: "动起来的一周"),
              momentKeys: ["commit", "sweat", "sore", "push", "flow", "strong", "proof"],
              blurb: .init(en: "Seven days of showing up sweaty.", zh: "连续七天，动起来。")),
        .init(symbol: "sunrise.fill", name: .init(en: "Morning Person", zh: "早起的人"),
              momentKeys: ["the_6am_test", "make_the_bed", "move_your_body", "no_phone", "real_breakfast", "sunlight", "your_best_morning"],
              blurb: .init(en: "Meet the version of you that wakes early.", zh: "遇见早起的自己。")),
        .init(symbol: "book.fill", name: .init(en: "Study Streak", zh: "学习打卡"),
              momentKeys: ["first_sitdown", "getting_into_it", "the_wall", "little_win", "refill_tank", "almost_there", "look_back"],
              blurb: .init(en: "One week, one subject, no excuses.", zh: "一周，一件事，不找借口。")),
        .init(symbol: "fork.knife", name: .init(en: "Eat Well", zh: "好好吃饭"),
              momentKeys: ["fridge_check", "cook_one_meal", "try_something_new", "meal_prep", "no_takeout", "share_a_meal", "favorite_dish"],
              blurb: .init(en: "A week of feeding yourself kindly.", zh: "好好吃饭的一周。")),
        .init(symbol: "figure.mind.and.body", name: .init(en: "Calm Week", zh: "平静一周"),
              momentKeys: ["one_deep_breath", "five_min_sit", "walk_no_phone", "journal", "stretch", "digital_sunset", "stillness"],
              blurb: .init(en: "A slower week, on purpose.", zh: "刻意慢下来的一周。")),
        .init(symbol: "paintpalette.fill", name: .init(en: "Make Something", zh: "做点东西"),
              momentKeys: ["blank_page", "first_mark", "ugly_middle", "keep_going", "detail", "almost", "finished_piece"],
              blurb: .init(en: "Blank page to finished piece.", zh: "从空白页，到完成品。")),
    ]

    /// All localized built-ins behind one language-stable lookup. Persisted
    /// challenges use the English identity key going forward, while matching
    /// both localized names keeps stories created by older app versions valid.
    static var allBuiltins: [ChallengeTemplate] {
        oneDayBuiltins + sevenDayBuiltins
    }

    static func builtIn(matching token: String?) -> ChallengeTemplate? {
        guard let token, !token.isEmpty else { return nil }
        return allBuiltins.first {
            token == $0.identityKey || token == $0.name.zh
        }
    }

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
        case id, emoji, symbol, name, momentKeys, momentTitles, blurb, isCustom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        emoji = (try? c.decode(String.self, forKey: .emoji)) ?? "🎬"
        isCustom = (try? c.decode(Bool.self, forKey: .isCustom)) ?? false
        blurb = try? c.decodeIfPresent(LocalizedText.self, forKey: .blurb)
        symbol = try? c.decodeIfPresent(String.self, forKey: .symbol)
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
        try c.encodeIfPresent(blurb, forKey: .blurb)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        try c.encode(isCustom, forKey: .isCustom)
    }
}
