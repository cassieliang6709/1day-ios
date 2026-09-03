import Foundation

/// What the new-story screen has currently got selected.
///
/// The composer used to keep only `templateID` and `mode`, and infer whether
/// the story was prompted from `selectedTemplate?.isTimeOnly != true`. That
/// inference is what made the screen jump: the recommendation grid stayed live
/// while "record by time" was chosen, so one tap on a poster silently rewrote
/// the template *and* flipped the mode cards above it. Making the style
/// explicit means the two selectors can never disagree, and the transitions
/// between them can be tested without a simulator.
struct ComposerSelection: Equatable {
    enum Style: Hashable {
        /// Live With Me — no prompts, clips land in the order they're filmed.
        case timeOnly
        /// A template's prompts, or the user's own from the guided flow.
        case prompted
    }

    private(set) var style: Style
    private(set) var templateID: UUID?
    private(set) var mode: Challenge.Mode

    /// The template grid only means anything when the story will have prompts
    /// at all. It used to gate `.disabled` + `.opacity(0.4)`; now it decides
    /// whether the grid is on screen, which is the same question asked once.
    var promptGridEnabled: Bool { style == .prompted }

    init(style: Style = .prompted, templateID: UUID? = nil, mode: Challenge.Mode = .oneDay) {
        self.style = style
        self.templateID = templateID
        self.mode = mode
    }

    /// What the screen opens on: a prompted story with the first recommendation
    /// already chosen, so "next" is reachable without a decision.
    static func initial(oneDay: [ChallengeTemplate]) -> ComposerSelection {
        var selection = ComposerSelection()
        selection.selectPrompted(in: oneDay)
        return selection
    }

    mutating func selectTimeOnly(in oneDay: [ChallengeTemplate]) {
        style = .timeOnly
        mode = .oneDay
        templateID = oneDay.first(where: \.isTimeOnly)?.id
    }

    /// `templates` is the list for the current mode. Keeps a template that
    /// already carries prompts — tapping the card you're on shouldn't reshuffle
    /// your choice — but always lands on `.prompted`, so the tap is never a
    /// no-op the way the old early return was.
    mutating func selectPrompted(in templates: [ChallengeTemplate]) {
        style = .prompted
        if let templateID, templates.contains(where: { $0.id == templateID && !$0.isTimeOnly }) {
            return
        }
        templateID = templates.first(where: { !$0.isTimeOnly })?.id
    }

    /// Picking a specific poster. Seven-day templates carry their own mode, so
    /// the grid can switch it without a separate control.
    mutating func select(
        _ template: ChallengeTemplate,
        oneDay: [ChallengeTemplate],
        sevenDay: [ChallengeTemplate]
    ) {
        mode = sevenDay.contains(where: { $0.id == template.id }) ? .sevenDay : .oneDay
        templateID = template.id
        style = template.isTimeOnly ? .timeOnly : .prompted
    }

    /// The guided flow writes the moments itself, so no template backs the
    /// story — but it is still very much a prompted one.
    mutating func useCustomPrompts() {
        style = .prompted
        mode = .oneDay
        templateID = nil
    }

    mutating func setMode(_ newMode: Challenge.Mode) {
        mode = newMode
    }

    /// Called after the mode changes. Seven-day has no time-only template, so
    /// that style can't survive the switch and the selection has to land on
    /// something that exists in the new mode.
    mutating func reconcileTemplate(
        oneDay: [ChallengeTemplate],
        sevenDay: [ChallengeTemplate]
    ) {
        let valid = mode == .oneDay ? oneDay : sevenDay
        if let template = valid.first(where: { $0.id == templateID }) {
            style = template.isTimeOnly ? .timeOnly : .prompted
            return
        }
        let preferred = valid.first { style == .timeOnly ? $0.isTimeOnly : !$0.isTimeOnly }
        guard let fallback = preferred ?? valid.first else {
            templateID = nil
            return
        }
        templateID = fallback.id
        style = fallback.isTimeOnly ? .timeOnly : .prompted
    }

    /// A deleted custom template leaves a dangling id; fall back to the first
    /// built-in with prompts rather than to nothing.
    mutating func clearTemplate(fallingBackTo templates: [ChallengeTemplate]) {
        style = .prompted
        mode = .oneDay
        templateID = templates.first(where: { !$0.isTimeOnly })?.id
    }
}
