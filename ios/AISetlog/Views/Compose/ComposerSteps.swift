import SwiftUI


enum ComposerLayout {
    static let margin: CGFloat = 16
    static let rowRadius: CGFloat = 16
}


enum ComposerEntry: Hashable {
    case writeList
    case byTime
}

struct WhatToFilmSection: View {
    let entry: ComposerEntry
    let onWriteList: () -> Void
    let onByTime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: Strings.composerWhatToFilm)
            ChoiceRow(
                title: Strings.composerWriteList, lead: Strings.composerWriteListLead,
                isOn: entry == .writeList,
                opensPage: true, icon: "checklist", action: onWriteList)
                .accessibilityIdentifier("write-own-entry")
            ChoiceRow(
                title: Strings.composerByTimeTitle, lead: Strings.composerByTimeLead,
                isOn: entry == .byTime, icon: "alarm.fill", action: onByTime)
                .accessibilityIdentifier("by-time-entry")
        }
        .padding(.horizontal, ComposerLayout.margin)
    }
}


struct DaysSection: View {
    @Binding var days: Challenge.Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: Strings.composerHowManyDays)
            ChoiceRow(
                title: Strings.composerPlanOneDay, lead: Strings.composerPlanOneDayLead,
                isOn: days == .oneDay) { days = .oneDay }
                .accessibilityIdentifier("plan-one-day")
            ChoiceRow(
                title: Strings.composerPlanSevenDay, lead: Strings.composerPlanSevenDayLead,
                isOn: days == .sevenDay) { days = .sevenDay }
                .accessibilityIdentifier("plan-seven-day")
        }
        .padding(.horizontal, ComposerLayout.margin)
    }
}

private struct ChoiceRow: View {
    let title: String
    let lead: String
    let isOn: Bool
    var opensPage = false
    var icon: String? = nil
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .animation(OneDay.Motion.snap, value: isOn)
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isOn ? Color.oneDayBrand : OneDay.inkFaint)
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.oneDayBrand)
                    .symbolEffect(.bounce, value: isOn)
                    .frame(width: 36, height: 36)
                    .background(Color.oneDayBrand.opacity(0.12), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(lead)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if opensPage {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OneDay.inkFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(OneDay.surface, in: shape)
        .overlay(shape.strokeBorder(
            isOn ? Color.oneDayBrand : OneDay.hairline, lineWidth: isOn ? 1.5 : 1))
        .contentShape(shape)
    }
}


struct SetupStep: View {
    @Binding var title: String
    @Binding var titleEdited: Bool
    let isOneDay: Bool
    let listCount: Int?
    let onOpenList: () -> Void

    @FocusState private var titleFocused: Bool
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    static func orientationIcon(_ orientation: Challenge.Orientation) -> String {
        switch orientation {
        case .portrait: "rectangle.portrait"
        case .landscape: "rectangle"
        case .square: "square"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            nameSection
        }
        .padding(.horizontal, ComposerLayout.margin)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: Strings.composerName)
            nameField
            if let listCount {
                ListSummaryRow(count: listCount, action: onOpenList)
            }
        }
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            TextField("", text: $title, prompt: Text(Strings.titlePrompt(oneDay: isOneDay)))
                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .tint(Color.oneDayBrand)
                .focused($titleFocused)
                .submitLabel(.done)
                .onChange(of: title) { _, _ in
                    if titleFocused { titleEdited = true }
                }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(OneDay.surface, in: RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous)
            .strokeBorder(OneDay.hairline, lineWidth: 1))
    }
}

private struct ListSummaryRow: View {
    let count: Int
    let action: () -> Void

    private var text: String {
        count > 0 ? Strings.composerListSummary(count) : Strings.composerListEmpty
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OneDay.brandText)
                Text(text)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(count > 0 ? OneDay.ink : OneDay.inkSoft)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OneDay.inkFaint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(OneDay.surface, in: RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous)
                .strokeBorder(OneDay.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("composer-list-summary")
    }
}

private struct CompanySegment: View {
    @Binding var withFriends: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                segment(Strings.composerFilmSolo, isOn: !withFriends, id: "company-solo") {
                    withFriends = false
                }
                segment(Strings.composerFilmTogether, isOn: withFriends, id: "company-with-friends") {
                    withFriends = true
                }
            }
            .padding(3)
            .background(OneDay.inkFaint.opacity(0.14), in: Capsule())

            Text(withFriends ? Strings.createWithFriendsCaption : Strings.createByYourselfCaption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .padding(.leading, 4)
        }
        .animation(OneDay.Motion.snap, value: withFriends)
    }

    private func segment(_ title: String, isOn: Bool, id: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: isOn ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isOn ? OneDay.ink : OneDay.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if isOn {
                        Capsule().fill(OneDay.surface).oneDaySoftShadow(strength: 0.5)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

