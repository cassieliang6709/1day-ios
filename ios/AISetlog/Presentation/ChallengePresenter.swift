import Foundation

struct ChallengePresenter {
    let challenge: Challenge

    var displayTitle: String { challenge.title }

    var unitName: String { Strings.unitName(oneDay: challenge.isOneDay) }
    var unitNamePlural: String { Strings.unitNamePlural(oneDay: challenge.isOneDay) }
    var storyLabel: String { Strings.storyLabel(oneDay: challenge.isOneDay) }

    func title(forSlot slot: Int) -> String {
        if let value = challenge.momentValue(forSlot: slot) {
            return MomentCatalog.localize(value)
        }
        return Strings.dayN(slot)
    }

    func momentName(forSlot slot: Int) -> String? {
        guard !challenge.isTimeOnly,
              let value = challenge.momentValue(forSlot: slot),
              !value.isEmpty
        else { return nil }
        return MomentCatalog.localize(value)
    }

    func slotLabel(forSlot slot: Int) -> String? {
        challenge.isShared ? momentName(forSlot: slot) : title(forSlot: slot)
    }
}
