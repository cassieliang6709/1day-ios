import Foundation

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
