import Foundation

struct Challenge: Codable, Identifiable {
    enum Mode: String, Codable, Hashable {
        case sevenDay
        case oneDay
    }

    enum Orientation: String, Codable, CaseIterable, Identifiable {
        case portrait
        case landscape
        case square

        var id: String { rawValue }

        var aspectRatio: CGFloat {
            switch self {
            case .portrait: 9 / 16
            case .landscape: 16 / 9
            case .square: 1
            }
        }

        var cropsAfterRecording: Bool { self == .square }
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
    var mode: Mode? = nil
    var clipLength: ClipLength? = nil
    var orientation: Orientation? = nil
    var cameraStyle: CameraStyle? = nil
    var templateName: String? = nil
    var momentTitles: [String]? = nil

    var roomCode: String? = nil
    var ownerName: String? = nil
    var ownerID: String? = nil

    var isShared: Bool { roomCode != nil }
    var resolvedMode: Mode { mode ?? .sevenDay }
    var resolvedClipLength: ClipLength { clipLength ?? .tiny }
    var resolvedOrientation: Orientation { orientation ?? .portrait }
    var isOneDay: Bool { resolvedMode == .oneDay }
    static let timeOnlyTemplateName = "Live With Me"
    var isTimeOnly: Bool { templateName == Self.timeOnlyTemplateName }

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
