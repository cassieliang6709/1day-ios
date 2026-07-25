import SwiftUI

/// Building blocks for `NewChallengeView` — the screen itself reads as a list
/// of sections; everything stateless lives here.

/// The caption-style section label shared by form sections.
struct FormSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(Color.oneDayBlue.opacity(0.62))
            .kerning(1.2)
    }
}

/// Big centered title + subtitle at the top of the creation form.
struct NewChallengeHeader: View {
    let oneDay: Bool
    let secondsLabel: String

    var body: some View {
        VStack(spacing: 8) {
            Text(Strings.headerTitle(oneDay: oneDay))
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.oneDayNavy)
                .multilineTextAlignment(.center)
            if !oneDay {
                Text(Strings.sevenDayHeaderSubtitle(secondsLabel: secondsLabel))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }
}


// MARK: - Template deck

/// Small capsule tag on the front template card (clip length, team/solo, mode).
private struct DeckChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.oneDayBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.oneDayMist, in: Capsule())
    }
}

/// One card in the deck: emoji tile, template name, moment caption, and chips
/// summarizing the current form choices. A blue check badge marks selection.
struct TemplateDeckCard: View {
    let template: ChallengeTemplate
    let secondsLabel: String
    let oneDay: Bool
    let withFriends: Bool
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(template.emoji)
                    .font(.system(size: 30))
                    .frame(width: 64, height: 64)
                    .background(
                        LinearGradient(
                            colors: [Color.oneDaySky, Color.oneDayBlue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Color.oneDayBlue, in: Circle())
                }
            }

            Text(template.displayName)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.oneDayNavy)

            if let count = template.momentTitles?.count {
                Text(Strings.templateMomentCount(count, secondsLabel: secondsLabel))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                DeckChip(icon: "clock", text: secondsLabel)
                DeckChip(
                    icon: withFriends ? "person.2.fill" : "person.fill",
                    text: withFriends ? Strings.withFriends : Strings.justMe)
                DeckChip(
                    icon: "calendar",
                    text: oneDay ? Strings.modeOneDay : Strings.modeSevenDay)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.oneDayBlue.opacity(selected ? 0.55 : 0.10),
                              lineWidth: selected ? 2 : 1)
        )
        .shadow(color: Color.oneDayBlue.opacity(0.14), radius: 18, y: 10)
    }
}

/// A fanned stack of template cards — swipe horizontally (or tap a back card)
/// to cycle; the front card is the selected template.
struct TemplateDeck: View {
    let templates: [ChallengeTemplate]
    let secondsLabel: String
    let oneDay: Bool
    let withFriends: Bool
    let selectedTemplate: ChallengeTemplate?
    /// Called whenever a different template reaches the front of the deck.
    let onFrontChange: (Int) -> Void

    @State private var frontIndex = 0
    @GestureState private var dragX: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<min(3, max(templates.count, 1)), id: \.self) { position in
                if templates.indices.contains(wrapped(position)) {
                    let index = wrapped(position)
                    card(at: index, position: position)
                }
            }
        }
        .frame(height: 250)
        .animation(.spring(duration: 0.35), value: frontIndex)
        .gesture(
            DragGesture(minimumDistance: 24)
                .updating($dragX) { value, state, _ in state = value.translation.width }
                .onEnded { value in
                    let swipe = value.translation.width
                    guard abs(swipe) > 48, templates.count > 1 else { return }
                    advance(by: swipe < 0 ? 1 : -1)
                }
        )
        .onChange(of: templates.map(\.id)) { _, _ in
            frontIndex = 0
            notify()
        }
        .onAppear(perform: notify)
    }

    /// Position 0 is the front card; 1 and 2 fan out behind it right / left.
    private func wrapped(_ position: Int) -> Int {
        (frontIndex + position) % templates.count
    }

    private func advance(by step: Int) {
        frontIndex = (frontIndex + step + templates.count) % templates.count
        notify()
    }

    private func notify() {
        guard templates.indices.contains(frontIndex) else { return }
        onFrontChange(frontIndex)
    }

    @ViewBuilder
    private func card(at index: Int, position: Int) -> some View {
        TemplateDeckCard(
            template: templates[index],
            secondsLabel: secondsLabel,
            oneDay: oneDay,
            withFriends: withFriends,
            selected: selectedTemplate == templates[index])
            .scaleEffect(position == 0 ? 1 : 0.86)
            .rotationEffect(.degrees(position == 1 ? 7 : position == 2 ? -7 : 0))
            .offset(
                x: position == 1 ? 42 : position == 2 ? -42 : dragX * 0.35,
                y: position == 0 ? 0 : 12)
            .opacity(position == 0 ? 1 : 0.6)
            .zIndex(Double(-position))
            .onTapGesture {
                if position != 0 {
                    frontIndex = index
                    notify()
                }
            }
    }
}

// MARK: - Option rows

/// A settings-style row: icon tile, title + subtitle, chevron. Used for the
/// secondary choices under the template deck.
struct FormListRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FormRowShell(icon: icon, title: title, subtitle: subtitle) {
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Same row style as `FormListRow`, but with a trailing toggle.
struct FormToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        FormRowShell(icon: icon, title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.oneDayBlue)
        }
    }
}

private struct FormRowShell<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.oneDayBlue)
                .frame(width: 44, height: 44)
                .background(Color.oneDayMist, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(14)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.oneDayBlue.opacity(0.06), radius: 10, y: 5)
    }
}

/// Bottom call-to-action, pinned above the safe area once the form is valid.
struct StartChallengeButton: View {
    let title: String
    let creating: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if creating {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                    Image(systemName: "arrow.right")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.oneDayBlue, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.oneDayBlue.opacity(0.24), radius: 12, y: 6)
        }
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.2), value: enabled)
    }
}
