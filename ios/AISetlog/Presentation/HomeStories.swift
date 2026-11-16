import Foundation

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

    var showsSection: Bool { !timeline.isEmpty }

    var sectionTitle: String? {
        isAnythingFilmed ? Strings.yourStories : nil
    }

    private var isAnythingFilmed: Bool {
        timeline.days.contains { day in
            day.stories.contains { $0.recordedCount > 0 }
        }
    }
}
