import SwiftUI

/// The app's entire navigation: two surfaces in a floating capsule.
///
/// It deliberately looks like an iOS floating control (Maps' mode switcher,
/// the Camera's photo/video selector) rather than a tab bar — 1Day has two
/// places to be, not a dashboard of sections.
struct FloatingTabBar<Tab: Hashable>: View {
    struct Item: Identifiable {
        let tab: Tab
        let label: String
        let icon: String
        let activeIcon: String
        var id: Tab { tab }

        init(tab: Tab, label: String, icon: String, activeIcon: String? = nil) {
            self.tab = tab
            self.label = label
            self.icon = icon
            self.activeIcon = activeIcon ?? icon
        }
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
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        .shadow(color: Color.oneDayNavy.opacity(0.16), radius: 20, y: 8)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segment(_ item: Item) -> some View {
        let isOn = item.tab == selection
        return Button {
            withAnimation(OneDay.Motion.snap) { selection = item.tab }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn ? item.activeIcon : item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(item.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isOn ? Color.white : OneDay.inkSoft)
            .padding(.vertical, 10)
            .padding(.horizontal, 22)
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
    }
}
