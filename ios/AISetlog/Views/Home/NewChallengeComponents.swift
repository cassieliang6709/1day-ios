import SwiftUI

/// Small building blocks for `NewChallengeView` — kept separate so the screen
/// itself reads as a list of sections.

/// The caption-style section label shared by every picker on the form.
struct FormSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(Color.oneDayBlue.opacity(0.62))
            .kerning(1.2)
    }
}

/// Big rounded title + subtitle at the top of the creation form.
struct NewChallengeHeader: View {
    let oneDay: Bool
    let secondsLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.headerTitle(oneDay: oneDay))
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.oneDayNavy)
            Text(Strings.headerSubtitle(oneDay: oneDay, secondsLabel: secondsLabel))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 28)
    }
}

/// Seven dots that light up one by one on appear — a hint at the 7-day story.
struct DayDots: View {
    let litDays: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...7, id: \.self) { day in
                ZStack {
                    Circle()
                        .fill(day <= litDays ? Color.oneDayBlue : .white)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.oneDayBlue.opacity(0.16), lineWidth: 1))
                    Text("\(day)")
                        .font(.footnote.bold())
                        .foregroundStyle(day <= litDays ? .white : Color.oneDayBlue.opacity(0.62))
                }
                .scaleEffect(day == litDays ? 1.12 : 1)
            }
        }
    }
}

/// Card-style picker for how long each clip runs.
struct ClipLengthPicker: View {
    @Binding var selection: Challenge.ClipLength

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormSectionHeader(text: Strings.clipLengthHeader)

            HStack(spacing: 10) {
                ForEach(Challenge.ClipLength.allCases) { length in
                    Button {
                        selection = length
                    } label: {
                        let selected = selection == length
                        VStack(alignment: .leading, spacing: 5) {
                            Text(length.secondsLabel)
                                .font(.title3.bold())
                            Text(Strings.clipLengthName(length))
                                .font(.subheadline.bold())
                            Text(Strings.clipLengthCaption(length))
                                .font(.caption2.weight(.semibold))
                                .opacity(0.68)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundStyle(selected ? Color.oneDayBlue : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            selected ? Color.oneDayBlue.opacity(0.12) : .white.opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(
                                    Color.oneDayBlue.opacity(selected ? 0.9 : 0.12),
                                    lineWidth: selected ? 2 : 1)
                        )
                        .shadow(color: Color.oneDayBlue.opacity(selected ? 0.12 : 0.06), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: selection)
                }
            }
        }
    }
}

/// One big gradient card in the swipeable template carousel, tinted by the
/// template's identity color. Custom templates can be deleted via context menu.
struct TemplateCard: View {
    let template: ChallengeTemplate
    let selected: Bool
    let secondsLabel: String
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        let tint = Identity.tint(for: template.identityKey)
        VStack(spacing: 14) {
            Text(template.emoji)
                .font(.system(size: 52))
            Text(template.displayName)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let count = template.momentTitles?.count {
                Text(Strings.templateMomentCount(count, secondsLabel: secondsLabel))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Text(selected ? Strings.selectedLabel : Strings.tapToSelect)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white.opacity(selected ? 0.34 : 0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: tint.opacity(0.35), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onTap)
        .sensoryFeedback(.selection, trigger: selected)
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(Strings.deleteTemplate, systemImage: "trash")
                }
            }
        }
    }
}

/// Dashed "make your own script" card at the end of the template carousel.
struct BuildYourOwnCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.oneDayBlue.opacity(0.7))
                Text(Strings.buildYourOwn)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text(Strings.pickYourPrompts)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Color.oneDayBlue.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Solo vs. shared-room choice.
struct AudiencePicker: View {
    @Binding var withFriends: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormSectionHeader(text: Strings.whosIn)

            HStack(spacing: 12) {
                modeCard(
                    icon: "person.fill", label: Strings.justMe,
                    caption: Strings.privateWeek, selected: !withFriends
                ) { withFriends = false }
                modeCard(
                    icon: "person.2.fill", label: Strings.withFriends,
                    caption: Strings.roomInvite, selected: withFriends
                ) { withFriends = true }
            }
        }
    }

    private func modeCard(
        icon: String, label: String, caption: String,
        selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.subheadline.bold())
                Text(caption)
                    .font(.caption)
                    .opacity(0.7)
            }
            .foregroundStyle(selected ? Color.oneDayBlue : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                selected ? Color.oneDayBlue.opacity(0.12) : .white.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.oneDayBlue.opacity(selected ? 0.82 : 0.12),
                                  lineWidth: selected ? 2 : 1)
            )
            .shadow(color: Color.oneDayBlue.opacity(selected ? 0.12 : 0.06), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
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
