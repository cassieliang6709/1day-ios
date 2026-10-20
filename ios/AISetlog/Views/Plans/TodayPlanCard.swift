import SwiftUI

/// 我的 → 今天的计划: today's list beside the mood, one row per item (1.5).
///
/// An item with footage is ticked — filming it is what ticks it, there is
/// no box to check by hand. Tapping an item films it. No count, no bar:
/// the list is what to film, not a score (PRD 5.6).
struct TodayPlanCard: View {
    let challenge: Challenge
    let progress: RoomProgress
    let onFilm: (Int) -> Void
    let onOpen: () -> Void

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: onOpen) {
                    Text(Strings.todaysPlanTitle)
                        .font(OneDay.Font.callout)
                        .foregroundStyle(OneDay.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-plan-open")

                ForEach(challenge.cards.map(\.day), id: \.self) { slot in
                    row(slot)
                }
            }
            // As tall as the mood card beside it.
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-plan-card")
    }

    private func row(_ slot: Int) -> some View {
        let done = progress.isFilled(slot)
        return Button { onFilm(slot) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(done ? Color.oneDayBrand : OneDay.inkFaint)
                Text(presenter.title(forSlot: slot))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(done ? .isSelected : [])
        .accessibilityIdentifier("today-plan-item")
    }
}
