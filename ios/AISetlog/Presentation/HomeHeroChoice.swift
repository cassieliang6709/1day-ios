import Foundation

/// What the top of the home screen leads with.
///
/// It used to lead with `min(by: recordedCount)` — "fewest moments filmed
/// wins" — so a story that had sat untouched for three days permanently
/// outranked the one being filmed today. That's why a story filmed on the 1st
/// was nowhere to be found on the 1st: an empty story was sitting on top of it.
///
/// The decision lives here rather than in the view because it depends on the
/// time of day, and a rule that behaves differently before and after noon is
/// only trustworthy if it can be tested at both.
enum HomeHeroChoice: Equatable {
    /// The story today is for. Titled 「今天的故事」.
    case today(Challenge)
    /// Nothing started today, but something is unfinished. Titled 「接着拍」.
    case resume(Challenge)
    /// Nothing to lead with — offer to start.
    case startToday

    /// The story being led with, if any.
    var challenge: Challenge? {
        switch self {
        case .today(let challenge), .resume(let challenge): challenge
        case .startToday: nil
        }
    }

    /// Hand-written because `Challenge` isn't `Equatable` and making it so
    /// would drag in reactions and comments, which have nothing to do with
    /// "is this the same story on the same footing".
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.today(l), .today(r)): l.id == r.id
        case let (.resume(l), .resume(r)): l.id == r.id
        case (.startToday, .startToday): true
        default: false
        }
    }

    /// Hour of day after which an unfinished story is presented as something to
    /// pick back up rather than as yesterday's leftovers. Before noon, a story
    /// started yesterday and left unfinished still reads as the current thing;
    /// the morning shouldn't pretend it's a clean slate.
    private static let afternoonHour = 12

    init(challenges: [Challenge], now: Date = .now, calendar: Calendar = .current) {
        let unfinished = challenges.filter { !$0.isComplete && !$0.cards.isEmpty }
        guard !unfinished.isEmpty else {
            self = .startToday
            return
        }

        // 1. Anything today is actually for wins outright.
        let forToday = unfinished.filter {
            Self.isForToday($0, now: now, calendar: calendar)
        }
        if let pick = Self.mostRecentlyActive(forToday, calendar: calendar) {
            self = .today(pick)
            return
        }

        // 2. Otherwise it depends on the time of day.
        let hour = calendar.component(.hour, from: now)
        if hour < Self.afternoonHour {
            let leftFromYesterday = unfinished.filter {
                Self.started($0, daysAgo: 1, now: now, calendar: calendar)
            }
            if let pick = Self.mostRecentlyActive(leftFromYesterday, calendar: calendar) {
                self = .resume(pick)
                return
            }
            self = .startToday
            return
        }

        if let pick = Self.mostRecentlyActive(unfinished, calendar: calendar) {
            self = .resume(pick)
            return
        }
        self = .startToday
    }

    /// Is this the story today is for?
    ///
    /// Seven-day challenges spanning a week is normal, so `startDate` being
    /// last Tuesday says nothing — what matters is whether today falls inside
    /// the week. One-day stories are the opposite: they're only today's if
    /// they started today.
    private static func isForToday(
        _ challenge: Challenge, now: Date, calendar: Calendar
    ) -> Bool {
        if challenge.isOneDay {
            return calendar.isDate(challenge.startDate, inSameDayAs: now)
        }
        // Deliberately not `challenge.currentDay`: that reads the clock itself,
        // which would make this untestable at a chosen time.
        let day = dayIndex(of: challenge, now: now, calendar: calendar)
        return (1...max(challenge.cards.count, 1)).contains(day)
    }

    /// 1-based day within the challenge, measured against `now`.
    private static func dayIndex(
        of challenge: Challenge, now: Date, calendar: Calendar
    ) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: challenge.startDate),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days + 1
    }

    private static func started(
        _ challenge: Challenge, daysAgo: Int, now: Date, calendar: Calendar
    ) -> Bool {
        guard let then = calendar.date(byAdding: .day, value: -daysAgo, to: now) else {
            return false
        }
        return calendar.isDate(challenge.startDate, inSameDayAs: then)
    }

    /// Most recently filmed wins; nothing filmed yet falls back to the newest
    /// story, because that's the one the person just set up.
    private static func mostRecentlyActive(
        _ challenges: [Challenge], calendar: Calendar
    ) -> Challenge? {
        challenges.max { lhs, rhs in
            let l = lhs.cards.compactMap(\.recordedAt).max()
            let r = rhs.cards.compactMap(\.recordedAt).max()
            switch (l, r) {
            case let (l?, r?): return l < r
            // Something filmed always beats something untouched.
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return lhs.startDate < rhs.startDate
            }
        }
    }
}
