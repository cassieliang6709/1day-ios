import SwiftUI

/// Buttons, chips and selectors. All of them are capsules — the app has one
/// control shape, which is most of what makes it feel like a single object
/// rather than a stack of forms.

// MARK: - Buttons

/// The primary action: a gradient capsule that glows and presses in.
/// One per screen, never two competing.
struct PrimaryActionStyle: ButtonStyle {
    var tint: LinearGradient = OneDay.brandHorizontal
    var glow: Color = .oneDayBrand

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, tint: tint, glow: glow)
    }

    /// A nested view rather than a plain modifier chain: `isEnabled` lives in
    /// the environment, and a `ButtonStyle` can't read it directly. Without
    /// this a disabled button looks exactly like a live one, which is a button
    /// telling the user something untrue about itself.
    private struct Surface: View {
        let configuration: Configuration
        let tint: LinearGradient
        let glow: Color

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(OneDay.Font.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(tint, in: Capsule())
                .oneDayGlow(glow, strength: glowStrength)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .animation(OneDay.Motion.snap, value: configuration.isPressed)
                .animation(OneDay.Motion.soft, value: isEnabled)
        }

        private var glowStrength: Double {
            guard isEnabled else { return 0 }
            return configuration.isPressed ? 0.5 : 1
        }
    }
}

/// The quieter sibling: white glass with blue type. For "maybe later" actions
/// that still deserve a full-width tap target.
struct SoftActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OneDay.Font.callout)
            // `brandText`, not the raw brand blue: 16pt is small type, and
            // #1677FF on white is 4.1:1.
            .foregroundStyle(OneDay.brandText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(OneDay.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
            .oneDaySoftShadow(strength: 0.6)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(OneDay.Motion.snap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryActionStyle {
    static var primaryAction: PrimaryActionStyle { PrimaryActionStyle() }
}

extension ButtonStyle where Self == SoftActionStyle {
    static var softAction: SoftActionStyle { SoftActionStyle() }
}

/// A circular glass icon button — back, share, close, more. iOS-native
/// floating control, sized for a comfortable thumb.
struct IconBubble: View {
    let systemName: String
    var size: CGFloat = 38
    var tint: Color = .oneDayNavy
    /// What VoiceOver says. Optional only so the call sites written before it
    /// existed still compile — without one, VoiceOver falls back to the SF
    /// Symbol's name ("xmark"), so every new caller should pass it.
    var label: String? = nil
    /// Sitting on a camera feed or a playing clip. Swaps the system material
    /// (which follows the device's appearance and goes white-on-white in
    /// light mode) for `OverVideoGlass`, and draws the glyph white.
    var overVideo = false
    let action: () -> Void

    /// Apple's minimum touch target. The bubble draws at `size` (38pt by
    /// default) because a 44pt disc reads as heavy in a nav bar; the button
    /// takes the full 44 around it so a thumb that lands just off the edge
    /// still counts.
    private static let minimumHitTarget: CGFloat = 44

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: size, height: size)
                .background { if !overVideo { Circle().fill(.regularMaterial) } }
                .modifier(BubbleChrome(overVideo: overVideo))
                .frame(minWidth: Self.minimumHitTarget, minHeight: Self.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.map { Text($0) } ?? Text(Image(systemName: systemName)))
    }

    /// A fixed point size, not a text style, on purpose: the glyph lives in a
    /// circle of fixed size, and letting Dynamic Type grow it would push it
    /// out through the edge. The label (`accessibilityLabel`) is what carries
    /// meaning for anyone who needs larger text.
    private var glyph: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(overVideo ? .white : tint)
    }

    private struct BubbleChrome: ViewModifier {
        let overVideo: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            if overVideo {
                content.overVideoControl(in: Circle())
            } else {
                content
                    .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    .oneDaySoftShadow(strength: 0.5)
            }
        }
    }
}

// MARK: - Chips

/// A small labelled capsule: clip length, moment count, privacy, mode.
/// Informational — chips never take taps.
struct OneDayChip: View {
    var icon: String?
    let text: String
    /// Defaults to `brandText`: a chip is 12pt type, below the size the raw
    /// brand blue is legible at.
    var tint: Color = OneDay.brandText
    /// On a photo or video, the chip needs its own scrim to stay readable.
    var onDark = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(OneDay.Font.rounded(.caption2, weight: .bold))
            }
            // A chip is a capsule; wrapping turns it into a blob. Anything too
            // long to fit is the caller passing the wrong string.
            Text(text)
                .font(OneDay.Font.caption)
                .lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(onDark ? .white : tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 6.5)
        .background {
            if onDark {
                Capsule().fill(.ultraThinMaterial)
            } else {
                Capsule().fill(tint.opacity(0.12))
            }
        }
    }
}

// MARK: - Selectors

/// A capsule segmented control. The selection slides between segments with
/// `matchedGeometryEffect`, which is what sells it as one physical object.
struct PillSelector<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var icon: String?
        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Value
    var compact = false

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(4)
        .background(OneDay.surfaceSoft.opacity(0.8), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segment(_ option: Option) -> some View {
        let isOn = option.value == selection
        return Button {
            withAnimation(OneDay.Motion.snap) { selection = option.value }
        } label: {
            HStack(spacing: 5) {
                if let icon = option.icon {
                    Image(systemName: icon).font(OneDay.Font.rounded(.caption2, weight: .bold))
                }
                Text(option.label)
                    .font(OneDay.Font.rounded(compact ? .footnote : .subheadline, weight: .bold))
            }
            .foregroundStyle(isOn ? .white : OneDay.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 7 : 9)
            .background {
                if isOn {
                    Capsule()
                        .fill(Color.oneDayBrand)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A settings-style row inside a glass card: icon tile, title, trailing value.
/// Used for the handful of choices in Create Room.
struct OptionRow<Trailing: View>: View {
    let icon: String
    let title: String
    var accent: Color = .oneDayBrand
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 13) {
            // Fixed size: the glyph sits in a fixed 34pt tile (see `IconBubble`).
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(title)
                .font(OneDay.Font.subhead)
                .foregroundStyle(OneDay.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)
            trailing
        }
    }
}

/// Section label above a group of cards. Small, muted, wide-tracked.
///
/// `inkSoft`, not `inkFaint`: a heading is how somebody finds their way down
/// a settings page, and at 12pt the faint ink is below the 4.5:1 that small
/// type needs.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OneDay.Font.rounded(.caption, weight: .bold))
            .kerning(0.9)
            .foregroundStyle(OneDay.inkSoft)
            .textCase(.uppercase)
    }
}
