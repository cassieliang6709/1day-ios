import Foundation

/// The time axis behind the vertical timeline.
///
/// A `Challenge` only knows a slot's *index* (`DayCard.day`) and, once filmed,
/// its `recordedAt`. The timeline needs a clock position for every slot —
/// including the empty ones — so it can lay a day out from top to bottom.
/// This derives one: moments spread evenly across a waking-day window that
/// begins at the story's start time.
///
/// Presentation only. Nothing here is persisted, so changing the shape of the
/// day never migrates anyone's saved stories.
struct StorySchedule {
    let challenge: Challenge

    /// How much of the day a 1-day story covers. 16 hours from the start time
    /// lands a 7-moment 4 AM story on 4 AM → 8 PM, which is what a day
    /// actually feels like.
    private static let dayWindow: TimeInterval = 16 * 3600

    init(_ challenge: Challenge) {
        self.challenge = challenge
    }

    private var slotCount: Int { max(challenge.cards.count, 1) }

    /// Where a slot sits on the clock if nobody has filmed it yet.
    func plannedDate(forSlot slot: Int) -> Date {
        let index = max(slot - 1, 0)
        guard challenge.isOneDay else {
            return Calendar.current.date(
                byAdding: .day, value: index,
                to: Calendar.current.startOfDay(for: challenge.startDate))
                ?? challenge.startDate
        }
        guard slotCount > 1 else { return challenge.startDate }
        let spacing = Self.dayWindow / Double(slotCount - 1)
        let raw = challenge.startDate.addingTimeInterval(spacing * Double(index))
        return Self.roundedToFiveMinutes(raw)
    }

    /// The rail label: a clock time for a 1-day film, a day number for a week.
    ///
    /// Deliberately the *planned* time, not `recordedAt`. The rail is the shape
    /// of the day, and it has to stay ordered and evenly spaced whether a
    /// moment was filmed on time, late, or not at all — three clips captured
    /// back-to-back in the evening should still read as morning, noon and
    /// night. When the moment was actually filmed is a detail for the clip
    /// preview, not the spine of the story.
    func railLabel(forSlot slot: Int) -> String {
        guard challenge.isOneDay else { return Strings.dayN(slot) }
        return Self.timeFormatter.string(from: plannedDate(forSlot: slot))
    }

    /// Secondary line under the rail label — the date for a 7-day story, so a
    /// week still reads as a stretch of real time.
    func railCaption(forSlot slot: Int) -> String? {
        guard !challenge.isOneDay else { return nil }
        return plannedDate(forSlot: slot).formatted(
            .dateTime.month(.abbreviated).day().locale(AppLanguage.effective.locale))
    }

    /// A small glyph for the part of the day a moment lands in. Purely
    /// atmospheric — it's what makes the rail read as a day passing.
    func dayPartIcon(forSlot slot: Int) -> String {
        let hour = Calendar.current.component(.hour, from: plannedDate(forSlot: slot))
        switch hour {
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

    /// "4:00 AM – 8:00 PM" (or the week's date range) for a story header.
    var spanLabel: String {
        let first = plannedDate(forSlot: 1)
        let last = plannedDate(forSlot: slotCount)
        if challenge.isOneDay {
            return "\(Self.timeFormatter.string(from: first)) – \(Self.timeFormatter.string(from: last))"
        }
        let fmt = Date.FormatStyle()
            .month(.abbreviated).day().locale(AppLanguage.effective.locale)
        return "\(first.formatted(fmt)) – \(last.formatted(fmt))"
    }

    // MARK: - Helpers

    private static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.effective.locale
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }

    /// Derived times land on ugly minutes (6:51 AM). Round so the rail reads
    /// like a plan someone wrote, not a computation.
    private static func roundedToFiveMinutes(_ date: Date) -> Date {
        let interval = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (interval / 300).rounded() * 300)
    }
}
