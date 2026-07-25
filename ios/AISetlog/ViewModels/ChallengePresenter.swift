import Foundation

/// Display text derived from a Challenge. Models stay UI-agnostic; anything
/// that needs a localized label for a challenge goes through here.
struct ChallengePresenter {
    let challenge: Challenge

    var unitName: String { Strings.unitName(oneDay: challenge.isOneDay) }
    var unitNamePlural: String { Strings.unitNamePlural(oneDay: challenge.isOneDay) }
    var storyLabel: String { Strings.storyLabel(oneDay: challenge.isOneDay) }

    /// The prompt shown for a slot, localized. `MomentCatalog.localize` resolves
    /// keys and legacy en/zh raw strings; slots without a stored value fall back
    /// to a generic "Day N" label.
    func title(forSlot slot: Int) -> String {
        if let value = challenge.momentValue(forSlot: slot) {
            return MomentCatalog.localize(value)
        }
        return Strings.dayN(slot)
    }
}
