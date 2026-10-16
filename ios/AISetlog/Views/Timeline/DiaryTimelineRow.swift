import SwiftUI

/// One line of the story page's diary: a big time on the left, a dot on a thin
/// rail, and whatever the row holds on the right.
///
/// The rail is drawn as the content's background, so it is always exactly as
/// tall as the row — a tall filmed row and a short empty one both join up with
/// their neighbours without measuring anything.
struct DiaryTimelineRow<Content: View>: View {
    /// HH:mm, or nil for a moment not filmed yet.
    let time: String?
    let isFirst: Bool
    let isLast: Bool
    /// Filled dot; otherwise a hollow one.
    let filmed: Bool
    /// Rings the dot: the moment the big button will open.
    var highlighted = false
    /// Paints the rail below this dot in brand colour — the next row is filmed too.
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
