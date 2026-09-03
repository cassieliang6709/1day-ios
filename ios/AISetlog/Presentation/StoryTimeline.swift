import Foundation

/// The stories you've made, grouped by the day they were for, newest first.
///
/// Home used to sort by state — "in progress" and "finished" — which is a
/// perfectly good answer to a question nobody asked. The question people
/// actually have is "what did I film on the 31st", and neither list could
/// answer it. This is the data behind scrolling back.
///
/// Empty days don't appear. A calendar full of blanks is a good way to tell
/// someone they've been failing; a list of the days that happened isn't.
struct StoryTimeline: Equatable {
    struct Day: Identifiable, Equatable {
        /// Start of the day, so two stories from the same afternoon collapse.
        var id: Date
        var date: Date
        /// "8月31日 周一" / "Mon, Aug 31"
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

    /// Whether anything in here is from today. Drives the section heading: a
    /// list headed "scroll back" whose first row says "today" isn't scrolling
    /// back to anything.
    let includesToday: Bool

    /// - Parameter heroID: the story already shown at the top of the screen.
    ///   It's excluded rather than duplicated — seeing today's story twice on
    ///   one screen is how the old home page got confusing in the first place.
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

        includesToday = days.contains { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// Which day a story belongs to.
    ///
    /// A seven-day challenge hangs off the day it started, whole. Splitting it
    /// across the week would scatter one film over seven entries, and the thing
    /// you go looking for is the film, not the clip.
    private static func day(of challenge: Challenge, calendar: Calendar) -> Date {
        challenge.startDate
    }

    /// Most recently filmed first within a day; untouched stories sink.
    private static func filmedLast(_ challenge: Challenge) -> Date {
        challenge.cards.compactMap(\.recordedAt).max() ?? challenge.startDate
    }

    /// "今天" and "昨天" beat a date string — they're what the day is called.
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
