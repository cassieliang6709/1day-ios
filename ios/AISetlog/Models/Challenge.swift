import Foundation

struct Challenge: Codable, Identifiable {
    enum Mode: String, Codable, Hashable {
        case sevenDay
        case oneDay
    }

    /// Recording frame orientation, locked per challenge so every clip in a
    /// film shares one aspect and the stitcher never mixes frames.
    enum Orientation: String, Codable, CaseIterable, Identifiable {
        case portrait
        case landscape

        var id: String { rawValue }

        /// Aspect (width / height) of the camera shell, board cards, preview.
        var aspectRatio: CGFloat {
            switch self {
            case .portrait: 9 / 14.3
            case .landscape: 14.3 / 9
            }
        }
    }

    enum ClipLength: String, Codable, CaseIterable, Identifiable {
        case tiny
        case story
        case scene

        var id: String { rawValue }

        var seconds: Double {
            switch self {
            case .tiny: 2
            case .story: 5
            case .scene: 10
            }
        }

    }

    let id: UUID
    var title: String
    var startDate: Date
    var cards: [DayCard]
    /// nil means an older saved challenge; treat it as the original 7-day flow.
    var mode: Mode? = nil
    /// nil means an older saved challenge; keep it on the original tiny clip.
    var clipLength: ClipLength? = nil
    /// nil means an older saved challenge; those are all portrait.
    var orientation: Orientation? = nil
    var templateName: String? = nil
    var momentTitles: [String]? = nil

    /// nil = local ("just me") challenge. Non-nil = shared CloudKit room whose
    /// 6-char join code this is. Optional so old saved data still decodes.
    var roomCode: String? = nil
    /// Display name of whoever created the room (shown in the roster).
    var ownerName: String? = nil
    /// Author id of whoever created the room, so the roster can show them
    /// before they've filmed anything. nil in rooms saved before this existed.
    var ownerID: String? = nil

    var isShared: Bool { roomCode != nil }
    var resolvedMode: Mode { mode ?? .sevenDay }
    var resolvedClipLength: ClipLength { clipLength ?? .tiny }
    var resolvedOrientation: Orientation { orientation ?? .portrait }
    var isOneDay: Bool { resolvedMode == .oneDay }
    var isTimeOnly: Bool { templateName == ChallengeTemplate.liveWithMeIdentityKey }

    /// 1-based index of "today" within the challenge (day 1 = startDate).
    /// Can exceed 7 once the week is over.
    var currentDay: Int {
        if isOneDay {
            let cal = Calendar.current
            let days = cal.dateComponents(
                [.day],
                from: cal.startOfDay(for: startDate),
                to: cal.startOfDay(for: .now)
            ).day ?? 0
            return days == 0 ? 1 : cards.count + 1
        }
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: startDate),
            to: cal.startOfDay(for: .now)
        ).day ?? 0
        return days + 1
    }

    var recordedCount: Int { cards.filter { $0.clipFileName != nil }.count }
    var isComplete: Bool { recordedCount == cards.count }

    /// The raw stored value for a slot's prompt — a stable moment *key* for new
    /// challenges, or a legacy raw display string from older saves. Localization
    /// and fallback labels are presentation concerns (see `ChallengePresenter`).
    func momentValue(forSlot slot: Int) -> String? {
        guard let momentTitles, momentTitles.indices.contains(slot - 1) else {
            return nil
        }
        return momentTitles[slot - 1]
    }

    func cardStatus(_ card: DayCard) -> DayCard.Status {
        if card.clipFileName != nil { return .done }
        if isOneDay {
            return currentDay > cards.count ? .missed : .today
        }
        return card.status(currentDay: currentDay)
    }
}
