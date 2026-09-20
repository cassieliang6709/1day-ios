import Foundation

/// The home screen's stories as one decision.
///
/// The hero and the list below it used to be worked out separately in the
/// view. Apart, each was right; together they left a gap — see `sectionTitle`.
///
/// Every story the app knows about appears here exactly once: as the hero, or
/// as a row. Filming has nothing to do with it — a story made ten seconds ago
/// and never pointed at anything is on the screen like any other.
struct HomeStories {
    let hero: HomeHeroChoice
    let timeline: StoryTimeline

    init(challenges: [Challenge], now: Date = .now, calendar: Calendar = .current) {
        hero = HomeHeroChoice(challenges: challenges, now: now, calendar: calendar)
        timeline = StoryTimeline(
            challenges: challenges,
            excluding: hero.challenge?.id,
            now: now,
            calendar: calendar)
    }

    /// Whether there's a list under the hero at all.
    var showsSection: Bool { !timeline.isEmpty }

    /// 「你的故事」, or nil when no story in the list has been filmed.
    ///
    /// The name itself is settled: it used to read 「往前翻」 whenever the list
    /// held nothing from today — and because the hero is lifted *out* of the
    /// list, that was exactly the day you made a story. Create one, don't film
    /// it, go home: your new story is the card on top, and the only list on the
    /// screen has renamed itself to a place nobody would look for something
    /// they just made. The list is your stories on whatever day they happened;
    /// that's its name.
    ///
    /// What's conditional is whether the heading is drawn at all. Product call
    /// (2026-09-18): with no footage anywhere in the list, the four characters
    /// come off the screen. The rows and their day labels stay — only the
    /// heading goes, so nothing becomes unreachable. It returns as soon as one
    /// story in the list has a clip.
    var sectionTitle: String? {
        isAnythingFilmed ? Strings.yourStories : nil
    }

    /// Whether any story in the list has at least one clip.
    ///
    /// The hero doesn't count: it's excluded from `timeline`, and the heading
    /// labels the list, not the screen.
    private var isAnythingFilmed: Bool {
        timeline.days.contains { day in
            day.stories.contains { $0.recordedCount > 0 }
        }
    }
}
