import SwiftUI

/// Legacy alias layer.
///
/// The redesign moved the palette into `OneDay` (Resources/Theme.swift). The
/// screens that weren't rebuilt — the recorder, the clip preview, settings,
/// the template builder — still reach for `BoardTheme`, so it stays as a thin
/// forwarding layer. That way they inherit the new colors without being
/// touched, and there's exactly one place to define a blue.
///
/// New code should use `OneDay` directly.
enum BoardTheme {
    static let primary = Color.oneDayBlue
    static let accent = Color.oneDayCyan
    static let deep = Color.oneDayNavy
    static let tint = Color.oneDaySky
    static let page = OneDay.canvas
    static let card = OneDay.surface.opacity(0.94)
    static let cardStrong = OneDay.surface
    static let stroke = OneDay.hairline
    static let primaryText = OneDay.ink
    static let secondaryText = OneDay.inkSoft

    static let background = LinearGradient(
        colors: [OneDay.canvas, OneDay.surface, OneDay.surfaceSoft.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    static let actionGradient = OneDay.brand
}

/// The old board background. Kept for the screens still using it; new screens
/// use `OneDayCanvas`.
struct BoardBackground: View {
    var body: some View {
        OneDayCanvas()
    }
}
