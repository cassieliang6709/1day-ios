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

    /// Always 「你的故事」.
    ///
    /// This used to read 「往前翻」 whenever the list held nothing from today —
    /// and because the hero is lifted *out* of the list, that was exactly the
    /// day you made a story. Create one, don't film it, go home: your new
    /// story is the card on top, and the only list on the screen has renamed
    /// itself to a place nobody would look for something they just made. The
    /// list is your stories on whatever day they happened; that's its name.
    var sectionTitle: String { Strings.yourStories }
}
