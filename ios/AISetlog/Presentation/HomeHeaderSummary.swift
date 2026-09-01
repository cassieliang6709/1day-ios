import Foundation

/// The two lines beside the avatar at the top of the home screen.
///
/// The header used to lead with the 1day wordmark, which is the one thing a
/// person opening 1day already knows. What they don't know is what day it is
/// and how much of it they've filmed — and until now the home screen said
/// neither, which is why a story filmed on the 1st was impossible to find by
/// date. Both facts live here rather than in the view so they can be tested
/// in both languages without a simulator.
struct HomeHeaderSummary {
    /// "9月1日 星期一" / "Mon, Sep 1".
    let dateLine: String
    /// Moments filmed in today's story. Nil when there is no active story —
    /// the header then shows the date alone rather than a hollow "0/0".
    let recorded: Int?
    /// Slots in today's story. Nil under the same condition as `recorded`.
    let total: Int?

    var hasProgress: Bool { recorded != nil && total != nil }

    /// "今天 1/7" / "Today 1/7". Empty when there's no active story.
    var progressLine: String {
        guard let recorded, let total else { return "" }
        return Strings.headerDateProgress(recorded, total)
    }

    init(date: Date = .now, challenge: Challenge?) {
        self.dateLine = Self.format(date)
        // A story with no slots can't express progress — `cards` is empty only
        // for malformed data, but "0/0" would still read as a real number.
        if let challenge, !challenge.cards.isEmpty {
            self.recorded = challenge.recordedCount
            self.total = challenge.cards.count
        } else {
            self.recorded = nil
            self.total = nil
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .weekday(.abbreviated)
                .locale(AppLanguage.effective.locale))
    }
}
