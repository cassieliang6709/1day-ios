import Foundation

struct HomeHeaderSummary {
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
