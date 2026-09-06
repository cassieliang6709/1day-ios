import Foundation

/// Finds a cover for a story nobody drew art for.
///
/// Every user-built template wore the same shared illustration, so a library
/// of your own scripts looked like one script printed six times. This reads
/// the moments you actually picked and lends them the built-in poster whose
/// day they most resemble. No network and no generation — it only hands out
/// artwork that already ships in the bundle.
enum TemplateCoverMatcher {
    /// Shown when nothing matches: better a deliberate blank poster than a
    /// wrong one.
    static let fallbackAssetName = "TemplateCustomStory"

    /// The best built-in cover for a set of moments, or nil when the moments
    /// say nothing recognisable and the caller should use `fallbackAssetName`.
    ///
    /// Two passes, in order of how much they actually know:
    /// 1. The moments are catalog keys shared with a built-in template — that
    ///    template's day *is* this day, so wear its poster.
    /// 2. Nothing overlaps (hand-typed prompts), so read the words. Each theme
    ///    below owns a few of them in both languages.
    static func assetName(forMomentKeys keys: [String], name: String = "") -> String? {
        sharedBuiltInCover(for: keys) ?? keywordCover(for: keys, name: name)
    }

    // MARK: Pass 1 — moments shared with a built-in

    private static func sharedBuiltInCover(for keys: [String]) -> String? {
        let normalized = Set(keys.map { MomentCatalog.key(forDisplay: $0) ?? $0 })
        guard !normalized.isEmpty else { return nil }

        var best: (asset: String, score: Int)?
        for template in ChallengeTemplate.allBuiltins {
            guard let asset = template.coverAssetName,
                  let moments = template.momentKeys
            else { continue }
            let score = moments.reduce(into: 0) { $0 += normalized.contains($1) ? 1 : 0 }
            // Strictly greater keeps the first built-in on a tie, so the same
            // moments always produce the same cover.
            guard score > 0, score > (best?.score ?? 0) else { continue }
            best = (asset, score)
        }
        return best?.asset
    }

    // MARK: Pass 2 — the words themselves

    /// Theme → words that mean it, English and Chinese. Ordered most specific
    /// first: "做饭" hits both cooking and making, and cooking should win.
    private static let keywordThemes: [(asset: String, words: [String])] = [
        ("TemplateCookWithMe",
         ["cook", "recipe", "kitchen", "bake", "做饭", "下厨", "厨房", "烘焙", "做菜", "炒"]),
        ("TemplateEatWell",
         ["breakfast", "lunch", "dinner", "meal", "eat", "food", "早餐", "午餐", "晚餐", "吃", "饭", "美食"]),
        ("TemplateStudyStreak",
         ["study", "exam", "homework", "class", "revise", "学习", "复习", "考试", "上课", "看书", "作业", "背"]),
        ("TemplateSevenDaysMoving",
         ["run", "gym", "workout", "training", "sweat", "swim", "跑", "健身", "锻炼", "运动", "训练", "游泳"]),
        ("TemplateMorningPerson",
         ["morning", "wake", "sunrise", "alarm", "早起", "早晨", "清晨", "起床", "闹钟"]),
        ("TemplateLittleAdventure",
         ["trip", "travel", "walk", "explore", "adventure", "outside", "出门", "旅行", "散步", "出发", "冒险", "逛"]),
        ("TemplateCalmWeek",
         ["calm", "rest", "quiet", "breathe", "sleep", "meditate", "休息", "放松", "安静", "冥想", "深呼吸", "睡"]),
        ("TemplateSoftReset",
         ["reset", "tidy", "clean", "declutter", "重启", "整理", "收拾", "打扫", "断舍离"]),
        ("TemplateLockIn",
         ["work", "focus", "deadline", "desk", "code", "ship", "工作", "专注", "加班", "代码", "项目", "赶"]),
        ("TemplateMainCharacter",
         ["outfit", "mirror", "selfie", "fit check", "穿搭", "镜子", "自拍", "主角", "打扮"]),
        ("TemplateMakeSomething",
         ["draw", "paint", "write", "craft", "build", "make", "画", "写", "手工", "创作", "做"]),
    ]

    private static func keywordCover(for keys: [String], name: String) -> String? {
        // Search both languages of every moment, not just the one on screen:
        // the prompts were typed in whichever language the user was thinking in.
        var haystack = name.lowercased()
        for key in keys {
            haystack += "\n" + MomentCatalog.localize(key, .english).lowercased()
            haystack += "\n" + MomentCatalog.localize(key, .chinese).lowercased()
        }
        guard !haystack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var best: (asset: String, score: Int)?
        for theme in keywordThemes {
            let score = theme.words.reduce(into: 0) {
                $0 += haystack.contains($1) ? 1 : 0
            }
            guard score > 0, score > (best?.score ?? 0) else { continue }
            best = (theme.asset, score)
        }
        return best?.asset
    }
}

extension ChallengeTemplate {
    /// The bundled art this template shows when the user hasn't uploaded a
    /// cover of their own. Built-ins keep their painted poster; everything
    /// else gets one matched to its moments.
    var matchedCoverAssetName: String {
        coverAssetName
            ?? TemplateCoverMatcher.assetName(forMomentKeys: momentKeys ?? [], name: name.en)
            ?? TemplateCoverMatcher.fallbackAssetName
    }
}
