import Foundation

enum HomeHeroChoice: Equatable {
    case today(Challenge)
    case resume(Challenge)
    case startToday

    var challenge: Challenge? {
        switch self {
        case .today(let challenge), .resume(let challenge): challenge
        case .startToday: nil
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.today(l), .today(r)): l.id == r.id
        case let (.resume(l), .resume(r)): l.id == r.id
        case (.startToday, .startToday): true
        default: false
        }
    }

    private static let afternoonHour = 12

    init(challenges: [Challenge], now: Date = .now, calendar: Calendar = .current) {
        let unfinished = challenges.filter { !$0.isComplete && !$0.cards.isEmpty }
        guard !unfinished.isEmpty else {
            self = .startToday
            return
        }

        let forToday = unfinished.filter {
            Self.isForToday($0, now: now, calendar: calendar)
        }
        if let pick = Self.mostRecentlyActive(forToday, calendar: calendar) {
            self = .today(pick)
            return
        }

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

    private static func isForToday(
        _ challenge: Challenge, now: Date, calendar: Calendar
    ) -> Bool {
        if challenge.isOneDay {
            return calendar.isDate(challenge.startDate, inSameDayAs: now)
        }
        let day = dayIndex(of: challenge, now: now, calendar: calendar)
        return (1...max(challenge.cards.count, 1)).contains(day)
    }

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

    private static func mostRecentlyActive(
        _ challenges: [Challenge], calendar: Calendar
    ) -> Challenge? {
        challenges.max { lhs, rhs in
            let l = lhs.cards.compactMap(\.recordedAt).max()
            let r = rhs.cards.compactMap(\.recordedAt).max()
            switch (l, r) {
            case let (l?, r?): return l < r
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return lhs.startDate < rhs.startDate
            }
        }
    }
}
