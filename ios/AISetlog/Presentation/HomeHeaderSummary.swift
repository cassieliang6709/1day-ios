import Foundation

/// The date line beside the avatar at the top of the home screen.
///
/// The header used to lead with the 1day wordmark, which is the one thing a
/// person opening 1day already knows; what they don't know is what day it is.
/// It also said how much of today's story was filmed (「今天 1/7」) until 1.5,
/// which dropped every count like it: a day isn't a quota. Lives here rather
/// than in the view so it can be tested in both languages without a simulator.
struct HomeHeaderSummary {
    /// "9月1日 星期一" / "Mon, Sep 1".
    let dateLine: String

    init(date: Date = .now) {
        self.dateLine = Self.format(date)
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
