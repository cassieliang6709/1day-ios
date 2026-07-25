import Foundation

struct Challenge: Codable, Identifiable {
    enum Mode: String, Codable, Hashable {
        case sevenDay
        case oneDay
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

        var secondsLabel: String {
            switch self {
            case .tiny: "2s"
            case .story: "5s"
            case .scene: "10s"
            }
        }

        var displayName: String {
            Strings.clipLengthName(self)
        }

        var caption: String {
            Strings.clipLengthCaption(self)
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
    var templateName: String? = nil
    var momentTitles: [String]? = nil

    /// nil = local ("just me") challenge. Non-nil = shared CloudKit room whose
    /// 6-char join code this is. Optional so old saved data still decodes.
    var roomCode: String? = nil
    /// Display name of whoever created the room (shown in the roster).
    var ownerName: String? = nil

    var isShared: Bool { roomCode != nil }
    var resolvedMode: Mode { mode ?? .sevenDay }
    var resolvedClipLength: ClipLength { clipLength ?? .tiny }
    var isOneDay: Bool { resolvedMode == .oneDay }

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

    var unitName: String { Strings.unitName(oneDay: isOneDay) }
    var unitNamePlural: String { Strings.unitNamePlural(oneDay: isOneDay) }
    var storyLabel: String { Strings.storyLabel(oneDay: isOneDay) }

    /// The prompt shown for a slot, localized. Stored `momentTitles` hold stable
    /// moment *keys* now, but legacy saved challenges/rooms may hold raw display
    /// strings — `MomentCatalog.localize` resolves all three (key, en, zh).
    func title(forSlot slot: Int) -> String {
        if let momentTitles, momentTitles.indices.contains(slot - 1) {
            return MomentCatalog.localize(momentTitles[slot - 1])
        }
        return Strings.dayN(slot)
    }

    func cardStatus(_ card: DayCard) -> DayCard.Status {
        if card.clipFileName != nil { return .done }
        if isOneDay {
            return currentDay > cards.count ? .missed : .today
        }
        return card.status(currentDay: currentDay)
    }
}
