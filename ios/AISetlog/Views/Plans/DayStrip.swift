import SwiftUI

/// 月历弹窗：有片段的日子标点，有心情的日子显示表情。选一天就关掉。
struct DayPickerSheet: View {
    @Binding var selected: Date
    let hasSomething: (Date) -> Bool
    var mood: (Date) -> Mood? = { _ in nil }

    @Environment(\.dismiss) private var dismiss
    @State private var month = Calendar.current.startOfDay(for: .now)
    private let calendar = Calendar.current

    static var title: String { AppLanguage.effective.resolved == .chinese ? "日历" : "Calendar" }
    static var backToToday: String { AppLanguage.effective.resolved == .chinese ? "回到今天" : "Back to today" }

    var body: some View {
        VStack(spacing: OneDay.Space.m) {
            HStack {
                IconBubble(systemName: "chevron.left") { shift(-1) }
                Spacer()
                Text(month.formatted(.dateTime.year().month(.wide).locale(AppLanguage.effective.locale)))
                    .font(OneDay.Font.headline)
                    .foregroundStyle(OneDay.ink)
                Spacer()
                IconBubble(systemName: "chevron.right") { shift(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OneDay.Space.xs), count: 7),
                      spacing: OneDay.Space.xs) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(OneDay.Font.caption)
                        .foregroundStyle(OneDay.inkFaint)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { cell(day) } else { Color.clear.frame(height: 1) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(OneDay.Space.xl)
        .onAppear { month = selected }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let start = interval.start
        let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        return Array(repeating: nil, count: lead)
            + (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func shift(_ months: Int) {
        withAnimation(OneDay.Motion.soft) {
            month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        }
    }

    private func cell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        return Button {
            selected = calendar.startOfDay(for: day)
            dismiss()
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(OneDay.Font.rounded(.subheadline, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? OneDay.onBrand : (isToday ? OneDay.brandText : OneDay.ink))
                ZStack {
                    if let mood = mood(day) {
                        // 固定尺寸：月历格子里的心情小图
                        Image(mood.imageName).resizable().scaledToFit().frame(width: 18, height: 18)
                    } else {
                        Circle()
                            .fill(isSelected ? OneDay.onBrand : Color.oneDayBrand)
                            .frame(width: 5, height: 5)
                            .opacity(hasSomething(day) ? 1 : 0)
                    }
                }
                .frame(height: 18)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, OneDay.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous)
                    .fill(isSelected ? Color.oneDayBrand : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct MoodDayCard: View {
    let entry: MoodEntry
    var wide = false

    var body: some View {
        GlassCard(padding: 14) {
            if wide {
                HStack(spacing: 14) {
                    face(64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Strings.moodDayLine(entry.mood))
                            .font(OneDay.Font.callout)
                            .foregroundStyle(OneDay.ink)
                        note
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    face(56)
                    Text(entry.mood.label)
                        .font(OneDay.Font.callout)
                        .foregroundStyle(OneDay.ink)
                    note
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mood-day-card")
    }

    private func face(_ size: CGFloat) -> some View {
        Image(entry.mood.imageName).resizable().scaledToFit().frame(width: size, height: size)
    }

    @ViewBuilder private var note: some View {
        if !entry.note.isEmpty {
            Text(entry.note)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DayRecapCard: View {
    let count: Int
    let onMake: () -> Void

    var body: some View {
        Button(action: onMake) {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.oneDayBrand)
                        .frame(height: 56, alignment: .leading)
                    Text(Strings.makeDayRecap)
                        .font(OneDay.Font.callout)
                        .foregroundStyle(OneDay.ink)
                    Text(Strings.libraryClipCount(count))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("day-recap")
    }
}
