import SwiftUI

struct ProgressRing: View {
    let recorded: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(BoardTheme.primary.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(recorded) / CGFloat(total))
                .stroke(
                    BoardTheme.actionGradient,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: recorded)
            Text("\(recorded)/\(total)")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(BoardTheme.primaryText)
        }
        .frame(width: 56, height: 56)
    }
}

