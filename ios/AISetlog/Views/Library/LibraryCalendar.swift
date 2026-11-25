import SwiftUI

struct LibraryCalendar: View {
    @Binding var month: Date
    let covers: [Date: LibraryClip]
    @Binding var selectedDay: Date?
    var showsMoods = false

    @Environment(MoodStore.self) private var moodStore: MoodStore?
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.year().month(.wide)))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OneDay.inkSoft)
            .buttonStyle(.plain)
            .frame(minHeight: 44)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 64) }
                }
            }
        }
        .padding(12)
        .glassSurface(radius: OneDay.Radius.card)
    }

    private func dayCell(_ date: Date) -> some View {
        let cover = covers[calendar.startOfDay(for: date)]
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isToday = calendar.isDateInToday(date)
        return Button {
            guard cover != nil else { return }
            selectedDay = isSelected ? nil : date
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday || cover != nil ? .heavy : .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        isSelected ? OneDay.onBrand
                            : isToday ? OneDay.brandText
                            : cover != nil ? OneDay.ink : OneDay.inkFaint)
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected { Circle().fill(Color.oneDayBrand) }
                    }
                dayMark(cover: cover, mood: mood(on: date))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cover == nil)
    }

    private func mood(on date: Date) -> Mood? {
        guard showsMoods else { return nil }
        return moodStore?.mood(on: date)?.mood
    }

    @ViewBuilder
    private func dayMark(cover: LibraryClip?, mood: Mood?) -> some View {
        if let mood {
            Image(mood.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: Self.markSize, height: Self.markSize)
                .accessibilityLabel(mood.label)
        } else if let cover {
            Color.clear
                .overlay { ClipThumbnail(url: cover.url, refreshToken: cover.recordedAt) }
                .clipShape(RoundedRectangle(cornerRadius: OneDay.Space.s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: OneDay.Space.s, style: .continuous).strokeBorder(.white, lineWidth: 1.5))
                .frame(width: Self.markSize, height: Self.markSize)
        } else {
            Color.clear.frame(width: Self.markSize, height: Self.markSize)
        }
    }

    private static let markSize: CGFloat = 28

    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: lead) + days.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        var localized = calendar
        localized.locale = AppLanguage.effective.locale
        let symbols = localized.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) {
            withAnimation(OneDay.Motion.snap) { month = next }
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
