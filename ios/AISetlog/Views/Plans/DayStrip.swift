import SwiftUI

/// The week across the top of 我的. Tap a day to see its plan; swipe for
/// the week before or after. A dot marks a day with a plan or a clip.
struct DayStrip: View {
    @Binding var selected: Date
    let hasSomething: (Date) -> Bool

    @State private var weekOffset = 0
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                cell(day)
            }
        }
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(OneDay.Motion.soft) { weekOffset += value.translation.width < 0 ? 1 : -1 }
            })
        .accessibilityIdentifier("day-strip")
    }

    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let first = calendar.date(byAdding: .day, value: weekOffset * 7, to: start) ?? start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private func cell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        return Button {
            withAnimation(OneDay.Motion.soft) { selected = day }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? OneDay.onBrand : OneDay.inkFaint)
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? OneDay.onBrand : (isToday ? OneDay.brandText : OneDay.ink))
                Circle()
                    .fill(isSelected ? OneDay.onBrand : Color.oneDayBrand)
                    .frame(width: 5, height: 5)
                    .opacity(hasSomething(day) ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.oneDayBrand : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("day-strip-day")
    }
}

/// A past day's mood, to look at: the face and the line written that day.
/// Not editable — a mood is filled in on the day or not at all.
struct MoodDayCard: View {
    let entry: MoodEntry

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(entry.mood.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                Text(entry.mood.label)
                    .font(OneDay.Font.callout)
                    .foregroundStyle(OneDay.ink)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mood-day-card")
    }
}
