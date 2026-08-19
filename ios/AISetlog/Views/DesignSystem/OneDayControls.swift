import SwiftUI

/// Buttons, chips and selectors. All of them are capsules — the app has one
/// control shape, which is most of what makes it feel like a single object
/// rather than a stack of forms.

// MARK: - Buttons

/// The primary action: a gradient capsule that glows and presses in.
/// One per screen, never two competing.
struct PrimaryActionStyle: ButtonStyle {
    var tint: LinearGradient = OneDay.brandHorizontal
    var glow: Color = .oneDayBlue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(tint, in: Capsule())
            .oneDayGlow(glow, strength: configuration.isPressed ? 0.5 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(OneDay.Motion.snap, value: configuration.isPressed)
    }
}

/// The quieter sibling: white glass with blue type. For "maybe later" actions
/// that still deserve a full-width tap target.
struct SoftActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.oneDayBlue)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .oneDaySoftShadow(strength: 0.5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chips

/// A small labelled capsule: clip length, moment count, privacy, mode.
/// Informational — chips never take taps.
struct OneDayChip: View {
    var icon: String?
    let text: String
    var tint: Color = .oneDayBlue
    /// On a photo or video, the chip needs its own scrim to stay readable.
    var onDark = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
            }
            // A chip is a capsule; wrapping turns it into a blob. Anything too
            // long to fit is the caller passing the wrong string.
            Text(text)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
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
                    Image(systemName: icon).font(.system(size: 11, weight: .bold))
                }
                Text(option.label)
                    .font(.system(size: compact ? 13 : 14.5, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isOn ? .white : OneDay.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 7 : 9)
            .background {
                if isOn {
                    Capsule()
                        .fill(Color.oneDayBlue)
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
    var accent: Color = .oneDayBlue
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)
            trailing
        }
    }
}

/// Section label above a group of cards. Small, blue, wide-tracked.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .kerning(0.9)
            .foregroundStyle(OneDay.inkFaint)
            .textCase(.uppercase)
    }
}
