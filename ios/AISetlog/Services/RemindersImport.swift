import EventKit
import Foundation

enum RemindersImport {
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let due: Date?
    }

    enum Outcome {
        case items([Item])
        case noAccess
    }

    static func load(store: EKEventStore = EKEventStore(), now: Date = .now) async -> Outcome {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else { return .noAccess }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        let items: [Item] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).compactMap { reminder -> Item? in
                    let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return nil }
                    return Item(
                        id: reminder.calendarItemIdentifier,
                        title: title,
                        due: reminder.dueDateComponents?.date)
                }
                continuation.resume(returning: items)
            }
        }
        return .items(ordered(items, now: now))
    }

    static func ordered(_ items: [Item], now: Date, calendar: Calendar = .current) -> [Item] {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        func rank(_ item: Item) -> Int {
            guard let due = item.due else { return 1 }
            return due < endOfToday ? 0 : 2
        }
        return items.sorted {
            let (a, b) = (rank($0), rank($1))
            if a != b { return a < b }
            if let x = $0.due, let y = $1.due, x != y { return x < y }
            return $0.title < $1.title
        }
    }
}
