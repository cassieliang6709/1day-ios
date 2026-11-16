import Foundation

struct StoryTimeline: Equatable {
    struct Day: Identifiable, Equatable {
        var id: Date
        var date: Date
        var label: String
        var stories: [Challenge]

        static func == (lhs: Day, rhs: Day) -> Bool {
            lhs.id == rhs.id
                && lhs.label == rhs.label
                && lhs.stories.map(\.id) == rhs.stories.map(\.id)
        }
    }

    let days: [Day]

    var isEmpty: Bool { days.isEmpty }

    init(
        challenges: [Challenge],
        excluding heroID: UUID? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let grouped = Dictionary(
            grouping: challenges.filter { $0.id != heroID },
            by: { calendar.startOfDay(for: Self.day(of: $0, calendar: calendar)) })

        days = grouped
            .map { start, stories in
                Day(
                    id: start,
                    date: start,
                    label: Self.label(for: start, now: now, calendar: calendar),
                    stories: stories.sorted { Self.filmedLast($0) > Self.filmedLast($1) })
            }
            .sorted { $0.date > $1.date }
    }

    private static func day(of challenge: Challenge, calendar: Calendar) -> Date {
        challenge.startDate
    }

    private static func filmedLast(_ challenge: Challenge) -> Date {
        challenge.cards.compactMap(\.recordedAt).max() ?? challenge.startDate
    }

    private static func label(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return Strings.todayLabel }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return Strings.yesterdayLabel
        }
        return date.formatted(
            .dateTime.month().day().weekday(.abbreviated)
                .locale(AppLanguage.effective.locale))
    }
}
