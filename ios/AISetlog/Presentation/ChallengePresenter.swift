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
    /// built-in poster when known, otherwise the closest poster its own
    /// moments can earn, and only then the universal custom-story cover.
    var coverAssetName: String {
        // A preset the person picked for this story wins: it is the only one
        // of these four that somebody chose on purpose.
        challenge.presetCoverAssetName
            ?? builtInTemplate?.coverAssetName
            ?? TemplateCoverMatcher.assetName(
                forMomentKeys: challenge.momentTitles ?? [], name: challenge.title)
            ?? TemplateCoverMatcher.fallbackAssetName
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

    /// The slot's own name, or nil when it has none — never 「第 N 天」.
    ///
    /// A shared room stopped numbering its days on screen (1.5): the page is
    /// a column of clips per person, each stamped with when it was filmed, and
    /// "Day 3" there is a label for nothing anyone can see. `title(forSlot:)`
    /// can't say "no name" — it has forty callers that need a string — so
    /// room screens ask this instead and draw the time on its own when it's
    /// nil. A 按时间 story has no names by definition.
    func momentName(forSlot slot: Int) -> String? {
        guard !challenge.isTimeOnly,
              let value = challenge.momentValue(forSlot: slot),
              !value.isEmpty
        else { return nil }
        return MomentCatalog.localize(value)
    }

    /// What a screen should call this slot: the solo wording for a solo story,
    /// and only a real name in a shared room. See `momentName(forSlot:)`.
    func slotLabel(forSlot slot: Int) -> String? {
        challenge.isShared ? momentName(forSlot: slot) : title(forSlot: slot)
    }
}
