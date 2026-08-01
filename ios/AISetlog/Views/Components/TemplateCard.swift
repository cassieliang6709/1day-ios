import SwiftUI

/// Choosing a story should feel like choosing a film to watch, not filling in
/// a field. Each template is a poster: a colored cover, a name, and one line
/// about how the day is supposed to feel.

struct TemplateCard: View {
    let template: ChallengeTemplate
    let secondsLabel: String
    let isOneDay: Bool
    /// The centre card is the selected one; neighbours sit back and desaturate.
    var isActive: Bool = true
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    private var momentCount: Int { template.momentKeys?.count ?? 7 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            details
        }
        .background(.background, in: RoundedRectangle(cornerRadius: OneDay.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OneDay.Radius.hero, style: .continuous)
                .strokeBorder(
                    isActive ? Color.oneDayBlue.opacity(0.35) : OneDay.hairline,
                    lineWidth: isActive ? 1.5 : 1)
        }
        .oneDaySoftShadow(strength: isActive ? 1.4 : 0.6)
    }

    // MARK: Cover

    private var cover: some View {
        ZStack {
            TemplateCover(identityKey: template.identityKey)

            Text(template.emoji)
                .font(.system(size: 62))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: OneDay.Radius.hero,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: OneDay.Radius.hero,
                style: .continuous))
        .overlay(alignment: .topTrailing) {
            if template.isCustom {
                Menu {
                    Button(Strings.editTemplate, systemImage: "pencil", action: onEdit ?? {})
                    Button(Strings.deleteTemplate, systemImage: "trash", role: .destructive, action: onDelete ?? {})
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(12)
            }
        }
        .overlay(alignment: .topLeading) {
            if template.isCustom {
                OneDayChip(icon: "sparkles", text: Strings.yoursLabel, onDark: true)
                    .padding(12)
            }
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(template.displayName)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(template.displayBlurb)
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .lineLimit(2)
                .frame(height: 38, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)

            // Two chips only. A third (the 1-Day/7-Day mode) overflows the card
            // width, and it's already stated by the heading and the selector
            // directly below the rack.
            HStack(spacing: 8) {
                OneDayChip(icon: "circle.grid.2x2.fill", text: Strings.momentsShort(momentCount))
                OneDayChip(
                    icon: "clock",
                    text: Strings.templateRuntime(
                        count: momentCount, secondsLabel: secondsLabel),
                    tint: .oneDayLavender)
            }
        }
        .padding(18)
    }
}

/// A soft two-tone cover, picked deterministically from the template's stable
/// English name so a story always wears the same colors.
struct TemplateCover: View {
    let identityKey: String

    private static let palettes: [[Color]] = [
        [.oneDaySky, .oneDayBlue],
        [.oneDayLavender, .oneDayBlue],
        [.oneDayMint, .oneDayCyan],
        [.oneDayButter, .oneDayBlush],
        [.oneDayCyan, .oneDayBlue],
        [.oneDayBlush, .oneDayLavender],
    ]

    private var colors: [Color] {
        let sum = identityKey.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palettes[sum % Self.palettes.count]
    }

    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                // A couple of soft blooms so the cover reads as light on a
                // surface rather than a flat swatch.
                ZStack {
                    Circle().fill(.white.opacity(0.18)).frame(width: 160).offset(x: -90, y: -60).blur(radius: 22)
                    Circle().fill(.black.opacity(0.07)).frame(width: 180).offset(x: 100, y: 70).blur(radius: 26)
                }
            }
    }
}

// MARK: - Carousel

/// Horizontal swipe deck. The centre card is active; neighbours peek in from
/// the sides so it's obvious there's more to see. Snapping and the scale
/// falloff are what make it feel like a physical rack of posters.
struct TemplateCarousel: View {
    let templates: [ChallengeTemplate]
    let secondsLabel: String
    let isOneDay: Bool
    @Binding var activeIndex: Int
    var onEdit: (ChallengeTemplate) -> Void = { _ in }
    var onDelete: (ChallengeTemplate) -> Void = { _ in }

    /// Bound to the scroll position; mirrored into `activeIndex`.
    @State private var scrolledID: Int?

    private let cardWidth: CGFloat = 278

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 16) {
                ForEach(Array(templates.enumerated()), id: \.offset) { index, template in
                    TemplateCard(
                        template: template,
                        secondsLabel: secondsLabel,
                        isOneDay: isOneDay,
                        isActive: index == activeIndex,
                        onEdit: { onEdit(template) },
                        onDelete: { onDelete(template) }
                    )
                    .frame(width: cardWidth)
                    .scrollTransition(axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.9)
                            .opacity(phase.isIdentity ? 1 : 0.55)
                            .rotation3DEffect(
                                .degrees(phase.value * -6),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.4)
                    }
                    .id(index)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, (UIScreen.main.bounds.width - cardWidth) / 2)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledID, anchor: .center)
        .sensoryFeedback(.selection, trigger: activeIndex)
        .onAppear { scrolledID = activeIndex }
        .onChange(of: scrolledID) { _, id in
            guard let id, id != activeIndex else { return }
            withAnimation(OneDay.Motion.soft) { activeIndex = id }
        }
        .onChange(of: templates.count) { _, count in
            // The deck changed under us (a custom script was added or removed).
            guard activeIndex >= count else { return }
            activeIndex = max(count - 1, 0)
            scrolledID = activeIndex
        }
    }
}

/// The dots under the carousel — position in the rack, at a glance.
struct CarouselDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(count, 1), id: \.self) { dot in
                Capsule()
                    .fill(dot == index ? Color.oneDayBlue : Color.oneDaySky.opacity(0.35))
                    .frame(width: dot == index ? 18 : 6, height: 6)
            }
        }
        .animation(OneDay.Motion.snap, value: index)
    }
}
