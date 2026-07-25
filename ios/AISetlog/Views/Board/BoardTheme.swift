import SwiftUI

enum BoardTheme {
    static let primary = Color.oneDayBlue
    static let accent = Color.oneDayCyan
    static let deep = Color.oneDayNavy
    static let tint = Color.oneDaySky
    static let page = Color.oneDayMist
    static let card = Color.white.opacity(0.92)
    static let cardStrong = Color.white
    static let stroke = Color.oneDayBlue.opacity(0.12)
    static let primaryText = Color(red: 0.05, green: 0.12, blue: 0.20)
    static let secondaryText = Color(red: 0.42, green: 0.49, blue: 0.57)

    static let background = LinearGradient(
        colors: [
            Color.oneDayMist,
            Color.white,
            Color(red: 0.88, green: 0.96, blue: 1.0),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let actionGradient = LinearGradient(
        colors: [primary, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct BoardBackground: View {
    var body: some View {
        ZStack {
            BoardTheme.background.ignoresSafeArea()
            Circle()
                .fill(BoardTheme.accent.opacity(0.16))
                .frame(width: 260, height: 260)
                .offset(x: -190, y: -260)
            Circle()
                .fill(BoardTheme.tint.opacity(0.18))
                .frame(width: 300, height: 300)
                .offset(x: 180, y: 360)
            Circle()
                .fill(BoardTheme.primary.opacity(0.08))
                .frame(width: 220, height: 220)
                .offset(x: -150, y: 460)
        }
    }
}
