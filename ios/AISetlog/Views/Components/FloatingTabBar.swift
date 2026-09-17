import SwiftUI

/// The app's entire navigation: three surfaces in a floating capsule.
///
/// It deliberately looks like an iOS floating control (Maps' mode switcher,
/// the Camera's photo/video selector) rather than a tab bar — 1Day has three
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
    /// Which segment is the one the app is *about*, drawn a step larger and in
    /// full ink even when it isn't selected. Nil for a bar where every segment
    /// is peer to the others.
    ///
    /// 1.3 puts 我的 in the middle and emphasises it. A three-segment capsule
    /// where all three look identical makes the user read all three every time;
    /// one of them being visibly the home screen means the other two are read
    /// as "somewhere else", which is what they are.
    var emphasisedIndex: Int? = nil

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                segment(item, emphasised: index == emphasisedIndex)
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        .shadow(color: Color.oneDayNavy.opacity(0.16), radius: 20, y: 8)
        .sensoryFeedback(.selection, trigger: selection)
        // Two segments had slack to spare; three do not. Plans/New/Camera is
        // ~295pt at the default size against an iPhone SE's 375, and the
        // capsule is centred with nothing to push, so an overflow here draws
        // 拍摄 off the edge of the screen rather than warning anybody. The
        // labels are two words in Chinese and one in English — there is
        // nothing to shrink — so the type size is what gets capped.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func segment(_ item: Item, emphasised: Bool = false) -> some View {
        let isOn = item.tab == selection
        return Button {
            withAnimation(OneDay.Motion.snap) { selection = item.tab }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn ? item.activeIcon : item.icon)
                    .font(.system(size: emphasised ? 15 : 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(item.label)
                    .font(.system(
                        size: emphasised ? 16 : 15,
                        weight: emphasised ? .bold : .semibold,
                        design: .rounded))
            }
            // Unselected, the emphasised segment still reads in full ink while
            // its neighbours sit back in `inkSoft`. That is the whole of the
            // emphasis when it isn't the current tab — no second background, no
            // badge: a permanently highlighted pill next to the selection pill
            // gives the bar two things that look selected.
            .foregroundStyle(isOn ? Color.white : (emphasised ? OneDay.ink : OneDay.inkSoft))
            .padding(.vertical, emphasised ? 11 : 10)
            // 22 with two segments, 16 with three: the capsule has to clear an
            // iPhone SE and the third label is what spent the margin. The
            // emphasised one buys its extra 4pt from its own neighbours, which
            // is why they went to 14.
            .padding(.horizontal, emphasised ? 18 : 14)
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
