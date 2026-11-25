import SwiftUI

struct RoomDateStrip: View {
    @Binding var selected: Date
    @Binding var anchor: Date
    @Binding var expanded: Bool
    let hasClips: (Date) -> Bool

    private let calendar = Calendar.current

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: OneDay.Space.xs), count: 7),
            spacing: OneDay.Space.xs
        ) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(OneDay.Font.micro)
                    .foregroundStyle(OneDay.inkFaint)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day { cell(day) } else { Color.clear.frame(height: 1) }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            shift(value.translation.width < 0 ? 1 : -1)
        })
        .accessibilityIdentifier("room-date-strip")
    }

    static func monthLabel(_ anchor: Date) -> String {
        let locale = AppLanguage.effective.locale
        if Calendar.current.isDate(anchor, equalTo: .now, toGranularity: .year) {
            return anchor.formatted(.dateTime.month(.abbreviated).locale(locale))
        }
        return anchor.formatted(.dateTime.year().month(.abbreviated).locale(locale))
    }

    private var cells: [Date?] {
        expanded ? monthCells : weekCells
    }

    private var weekCells: [Date?] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: anchor) else { return [] }
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    private var monthCells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        let start = interval.start
        let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        return Array(repeating: nil, count: lead)
            + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekdaySymbols: [String] {
        var localized = calendar
        localized.locale = AppLanguage.effective.locale
        let symbols = localized.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func shift(_ step: Int) {
        let unit: Calendar.Component = expanded ? .month : .weekOfYear
        guard let next = calendar.date(byAdding: unit, value: step, to: anchor),
              let start = calendar.dateInterval(of: unit, for: next)?.start,
              start <= .now
        else { return }
        withAnimation(OneDay.Motion.snap) { anchor = next }
    }

    private func pick(_ day: Date) {
        selected = calendar.startOfDay(for: day)
        anchor = selected
        if expanded {
            withAnimation(OneDay.Motion.snap) { expanded = false }
        }
    }

    private func numberColor(selected isSelected: Bool, today: Bool, enabled: Bool) -> Color {
        if isSelected { return OneDay.onBrand }
        if today { return OneDay.brandText }
        if enabled { return OneDay.ink }
        return OneDay.inkFaint
    }

    private func cell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let filmed = hasClips(day)
        let enabled = isToday || (filmed && day < .now)
        return Button { pick(day) } label: {
            VStack(spacing: .zero) {
                Text("\(calendar.component(.day, from: day))")
                    .font(OneDay.Font.rounded(.subheadline, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(numberColor(selected: isSelected, today: isToday, enabled: enabled))
                Circle()
                    .fill(isSelected ? OneDay.onBrand : OneDay.brandText)
                    .frame(width: 5, height: 5)
                    .opacity(filmed ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous)
                    .fill(isSelected ? Color.oneDayBrand : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(day.formatted(.dateTime.month().day().locale(AppLanguage.effective.locale)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
