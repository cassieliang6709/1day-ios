import SwiftUI

/// Camera and rooms share one compact navigation control.
struct FloatingTabBar<Tab: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    struct Item: Identifiable {
        let tab: Tab
        let label: String
        let icon: String
        let activeIcon: String
        let identifier: String
        var id: Tab { tab }
    }

    let items: [Item]
    @Binding var selection: Tab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                segment(item)
            }
        }
        .padding(5)
        .background { Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1) }
        .background(.regularMaterial, in: Capsule())
        .shadow(color: Color.oneDayNavy.opacity(0.16), radius: 20, y: 8)
        .sensoryFeedback(.selection, trigger: selection)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func segment(_ item: Item) -> some View {
        let isOn = item.tab == selection
        return Button {
            withAnimation(reduceMotion ? nil : OneDay.Motion.snap) { selection = item.tab }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? item.activeIcon : item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(item.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isOn ? OneDay.onBrand : OneDay.inkSoft)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background {
                if isOn {
                    Capsule()
                        .fill(OneDay.brandHorizontal)
                        .matchedGeometryEffect(id: "tab", in: indicator)
                        .oneDayGlow(strength: 0.7)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(item.identifier)
    }
}
