import Foundation

struct StorySchedule {
    let challenge: Challenge

    init(_ challenge: Challenge) {
        self.challenge = challenge
    }

    func railLabel(forSlot slot: Int, recordedAt: Date?) -> String? {
        guard challenge.isOneDay || challenge.isShared else { return Strings.dayN(slot) }
        guard let recordedAt else { return nil }
        return Self.timeFormatter.string(from: recordedAt)
    }

    func railCaption(forSlot slot: Int, recordedAt: Date?) -> String? {
        guard !challenge.isOneDay else { return nil }
        guard let recordedAt else { return nil }
        return recordedAt.formatted(
            .dateTime.month(.abbreviated).day().locale(AppLanguage.effective.locale))
    }

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

    func filmDuration(clipCount: Int? = nil) -> String {
        let count = clipCount ?? challenge.recordedCount
        let seconds = Int(
            (challenge.resolvedClipLength.seconds * Double(count)).rounded())
        return Strings.seconds(max(seconds, 0))
    }

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
