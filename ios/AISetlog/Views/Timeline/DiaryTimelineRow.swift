import SwiftUI

struct DiaryTimelineRow<Content: View>: View {
    let time: String?
    let isFirst: Bool
    let isLast: Bool
    let filmed: Bool
    var highlighted = false
    var railReached = false
    @ViewBuilder let content: Content

    static var timeWidth: CGFloat { 60 }
    private static var dotY: CGFloat { 15 }
    private static var railWidth: CGFloat { 14 }
    private static var gap: CGFloat { 18 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            timeLabel
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Self.railWidth + 12)
                .padding(.bottom, isLast ? 0 : Self.gap)
                .background(alignment: .topLeading) { rail }
        }
    }

    private var timeLabel: some View {
        Text(time ?? " ")
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(OneDay.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: Self.timeWidth, alignment: .trailing)
            .padding(.top, 1)
            .accessibilityHidden(true)
    }

    private var rail: some View {
        ZStack(alignment: .top) {
            if !isLast {
                line(reached: railReached)
                    .padding(.top, Self.dotY)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            if !isFirst {
                line(reached: filmed)
                    .frame(height: Self.dotY)
            }
            dot.padding(.top, Self.dotY - 6)
        }
        .frame(width: Self.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }

    private func line(reached: Bool) -> some View {
        Rectangle()
            .fill(reached
                ? AnyShapeStyle(Color.oneDayBrand)
                : AnyShapeStyle(OneDay.inkFaint.opacity(0.38)))
            .frame(width: 2)
    }

    private var dot: some View {
        Circle()
            .fill(filmed ? Color.oneDayBrand : OneDay.surface)
            .frame(width: 12, height: 12)
            .overlay {
                Circle().strokeBorder(
                    filmed || highlighted ? Color.oneDayBrand : OneDay.inkFaint.opacity(0.5),
                    lineWidth: 2)
            }
            .background {
                if highlighted {
                    Circle().fill(Color.oneDayBrand.opacity(0.16)).frame(width: 22, height: 22)
                }
            }
    }
}
