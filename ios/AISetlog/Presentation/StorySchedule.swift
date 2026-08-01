import Foundation

/// Time labels for the story timeline.
///
/// There is no schedule. You film a moment whenever it happens, and the
/// timeline stamps it with when that was — an earlier version spread slots
/// evenly across an invented 16-hour day, which put confident times next to
/// moments nobody had filmed yet. A slot with no clip has no time, and says so
/// by showing nothing.
///
/// A 7-day story is the exception: "Day 3" is a real fact about the plan, not
/// a guess, so the rail keeps showing it whether or not the clip exists.
struct StorySchedule {
    let challenge: Challenge

    init(_ challenge: Challenge) {
        self.challenge = challenge
    }

    /// The rail label. Nil for a 1-day moment that hasn't been filmed —
    /// the caller leaves the column blank rather than inventing a time.
    func railLabel(forSlot slot: Int, recordedAt: Date?) -> String? {
        guard challenge.isOneDay else { return Strings.dayN(slot) }
        guard let recordedAt else { return nil }
        return Self.timeFormatter.string(from: recordedAt)
    }

    /// Secondary line under the rail label — the date for a 7-day story, so a
    /// week still reads as a stretch of real time.
    func railCaption(forSlot slot: Int, recordedAt: Date?) -> String? {
        guard !challenge.isOneDay else { return nil }
        guard let recordedAt else { return nil }
        return recordedAt.formatted(
            .dateTime.month(.abbreviated).day().locale(AppLanguage.effective.locale))
    }

    /// A glyph for the part of the day a moment landed in. Atmospheric — it's
    /// what makes a filled rail read as a day passing. Nil until it's filmed.
    func dayPartIcon(recordedAt: Date?) -> String? {
        guard let recordedAt else { return nil }
        switch Calendar.current.component(.hour, from: recordedAt) {
        case 0..<5: return "moon.stars.fill"
        case 5..<9: return "sunrise.fill"
        case 9..<16: return "sun.max.fill"
        case 16..<20: return "sun.horizon.fill"
        default: return "moon.fill"
        }
    }

    /// Total runtime of the finished film, for the "14s" chip.
    var filmDuration: String {
        let seconds = Int(
            (challenge.resolvedClipLength.seconds * Double(challenge.recordedCount)).rounded())
        return Strings.seconds(max(seconds, 0))
    }

    /// The header line: the real span of what's been filmed so far
    /// ("9:15 AM – 6:40 PM"), or the story's date before anything exists.
    var spanLabel: String {
        let stamps = challenge.cards.compactMap(\.recordedAt).sorted()
        let dateFmt = Date.FormatStyle()
            .month(.abbreviated).day().locale(AppLanguage.effective.locale)

        guard challenge.isOneDay else {
            let start = challenge.startDate
            let end = Calendar.current.date(
                byAdding: .day, value: max(challenge.cards.count - 1, 0), to: start) ?? start
            return "\(start.formatted(dateFmt)) – \(end.formatted(dateFmt))"
        }

        guard let first = stamps.first, let last = stamps.last else {
            return challenge.startDate.formatted(dateFmt)
        }
        let from = Self.timeFormatter.string(from: first)
        let to = Self.timeFormatter.string(from: last)
        // Everything so far landed in the same minute — "10:00 PM – 10:00 PM"
        // is a range of nothing.
        guard from != to else { return from }
        return "\(from) – \(to)"
    }

    private static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.effective.locale
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }
}
