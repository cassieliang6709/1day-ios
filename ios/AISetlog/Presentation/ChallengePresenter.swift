import Foundation

/// Display text derived from a Challenge. Models stay UI-agnostic; anything
/// that needs a localized label for a challenge goes through here.
struct ChallengePresenter {
    let challenge: Challenge

    private var builtInTemplate: ChallengeTemplate? {
        ChallengeTemplate.builtIn(matching: challenge.templateName)
            ?? ChallengeTemplate.builtIn(matching: challenge.title)
    }

    /// Built-in default titles follow the app language. A title the user has
    /// edited remains exactly as authored, regardless of language changes.
    var displayTitle: String {
        guard let template = builtInTemplate,
              challenge.title == template.name.en || challenge.title == template.name.zh
        else { return challenge.title }
        return template.displayName
    }

    /// Every story has real artwork before its first recorded frame: its
    /// built-in poster when known, otherwise the universal custom-story cover.
    var coverAssetName: String {
        builtInTemplate?.coverAssetName ?? "TemplateCustomStory"
    }

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
