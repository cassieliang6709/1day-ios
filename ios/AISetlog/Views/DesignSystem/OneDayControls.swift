import SwiftUI



struct PrimaryActionStyle: ButtonStyle {
    var tint: LinearGradient = OneDay.brandHorizontal
    var glow: Color = .oneDayBrand

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, tint: tint, glow: glow)
    }

    private struct Surface: View {
        let configuration: Configuration
        let tint: LinearGradient
        let glow: Color

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(OneDay.Font.headline)
                .foregroundStyle(OneDay.onBrand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(tint, in: Capsule())
                .oneDayGlow(glow, strength: glowStrength)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
                .animation(OneDay.Motion.reduced(OneDay.Motion.snap, if: reduceMotion), value: configuration.isPressed)
                .animation(OneDay.Motion.reduced(OneDay.Motion.soft, if: reduceMotion), value: isEnabled)
        }

        private var glowStrength: Double {
            guard isEnabled else { return 0 }
            return configuration.isPressed ? 0.5 : 1
        }
    }
}

struct SoftActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration)
    }

    private struct Surface: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(OneDay.Font.callout)
                .foregroundStyle(OneDay.brandText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(OneDay.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
                .oneDaySoftShadow(strength: isEnabled ? 0.6 : 0)
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
                .animation(OneDay.Motion.reduced(OneDay.Motion.snap, if: reduceMotion), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PrimaryActionStyle {
    static var primaryAction: PrimaryActionStyle { PrimaryActionStyle() }
}

extension ButtonStyle where Self == SoftActionStyle {
    static var softAction: SoftActionStyle { SoftActionStyle() }
}

struct IconBubble: View {
    let systemName: String
    var size: CGFloat = 38
    var tint: Color = .oneDayNavy
    var label: String? = nil
    var overVideo = false
    let action: () -> Void

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


struct OneDayChip: View {
    var icon: String?
    let text: String
    var tint: Color = OneDay.brandText
    var onDark = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(OneDay.Font.rounded(.caption2, weight: .bold))
            }
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
            .foregroundStyle(isOn ? OneDay.onBrand : OneDay.inkSoft)
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

struct OptionRow<Trailing: View>: View {
    let icon: String
    let title: String
    var accent: Color = .oneDayBrand
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 13) {
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
