import Foundation
import SwiftUI

/// A stable visual identity (color + initial) derived from a recorder's
/// name — used to tell whose clip is whose in a shared room, instead of the
/// old free-choice "sticker pack". `MemberChip` (ChallengeBoardView) shares
/// this same palette so a person's color matches everywhere in the app.
enum Identity {
    static let paletteUIColors: [UIColor] = [
        UIColor(Color.setlogNavy), UIColor(Color.setlogBlue), UIColor(Color.setlogCyan),
        UIColor(Color.setlogSky), .systemTeal, .systemBlue,
    ]

    static func uiColor(for name: String?) -> UIColor {
        guard let name, !name.isEmpty else { return UIColor(Color.setlogBlue) }
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return paletteUIColors[sum % paletteUIColors.count]
    }

    static func tint(for name: String?) -> Color {
        Color(uiColor: uiColor(for: name))
    }

    /// Falls back to the app's brand mark when there's no one to identify
    /// (a solo challenge has no recorded author).
    static func initial(for name: String?) -> String {
        guard let name, let first = name.first else { return "1D" }
        return String(first).uppercased()
    }
}

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
            switch self {
            case .tiny: "Tiny"
            case .story: "Story"
            case .scene: "Scene"
            }
        }

        var caption: String {
            switch self {
            case .tiny: "Blink-and-done"
            case .story: "A fuller beat"
            case .scene: "Let it breathe"
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

    var unitName: String { isOneDay ? "moment" : "day" }
    var unitNamePlural: String { isOneDay ? "moments" : "days" }
    var storyLabel: String { isOneDay ? "1-day film" : "7-day challenge" }

    func title(forSlot slot: Int) -> String {
        if let momentTitles, momentTitles.indices.contains(slot - 1) {
            return momentTitles[slot - 1]
        }
        return "Day \(slot)"
    }

    func cardStatus(_ card: DayCard) -> DayCard.Status {
        if card.clipFileName != nil { return .done }
        if isOneDay {
            return currentDay > cards.count ? .missed : .today
        }
        return card.status(currentDay: currentDay)
    }
}

/// A named, ordered list of moment prompts. Built-in templates ship with the
/// app; custom ones are user-assembled in `BuildTemplateView` and persisted
/// by `ChallengeStore`.
struct ChallengeTemplate: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var emoji: String
    var name: String
    var momentTitles: [String]?
    /// Built-ins are identified by name (stable across app versions); custom
    /// ones by their generated id, since a user could name two the same.
    var isCustom: Bool = false

    static func == (lhs: ChallengeTemplate, rhs: ChallengeTemplate) -> Bool {
        lhs.isCustom ? lhs.id == rhs.id : lhs.name == rhs.name
    }

    static let oneDayBuiltins: [ChallengeTemplate] = [
        .init(
            emoji: "🌿", name: "Soft Reset",
            momentTitles: ["Before shot", "Clear one thing", "Reset corner", "Fresh air", "Tiny treat", "Cozy detail", "After shot"]),
        .init(
            emoji: "✍️", name: "Deep Focus",
            momentTitles: ["Setup", "First sprint", "Notes", "Snack break", "Messy middle", "Solved bit", "Done"]),
        .init(
            emoji: "🪄", name: "Room Flip",
            momentTitles: ["Before room", "Floor check", "Desk reset", "Closet pass", "Trash run", "Best detail", "After room"]),
        .init(
            emoji: "✨", name: "Main Character",
            momentTitles: ["Morning", "Move", "Outfit", "Food", "Little win", "Mirror check", "Night"]),
        .init(
            emoji: "💌", name: "Out Together",
            momentTitles: ["Meet", "Walk", "Food", "Laugh", "Side quest", "Favorite clip", "Bye"]),
    ]

    static let sevenDayBuiltins: [ChallengeTemplate] = [
        .init(emoji: "💪", name: "Workouts", momentTitles: nil),
        .init(emoji: "🥗", name: "Healthy Cooking", momentTitles: nil),
        .init(emoji: "🌅", name: "Morning Routines", momentTitles: nil),
        .init(emoji: "📚", name: "Studying", momentTitles: nil),
        .init(emoji: "🧘", name: "Meditation", momentTitles: nil),
        .init(emoji: "🎨", name: "Making Art", momentTitles: nil),
    ]

    /// Every individual moment prompt across the built-in 1-day templates,
    /// deduplicated and in first-seen order — the pool `BuildTemplateView` picks from.
    static let promptPool: [String] = {
        var seen = Set<String>()
        var pool: [String] = []
        for template in oneDayBuiltins {
            for prompt in template.momentTitles ?? [] where seen.insert(prompt).inserted {
                pool.append(prompt)
            }
        }
        return pool
    }()

    /// A fitting SF Symbol per built-in prompt, for the board's unrecorded
    /// slots — every prompt in `promptPool` is covered, since that's the
    /// finite set custom templates draw from too.
    private static let promptIcons: [String: String] = [
        "Before shot": "clock.arrow.circlepath",
        "Clear one thing": "checkmark.circle.fill",
        "Reset corner": "arrow.triangle.2.circlepath",
        "Fresh air": "wind",
        "Tiny treat": "cup.and.saucer.fill",
        "Cozy detail": "house.fill",
        "After shot": "checkmark.seal.fill",
        "Setup": "gearshape.fill",
        "First sprint": "bolt.fill",
        "Notes": "note.text",
        "Snack break": "fork.knife",
        "Messy middle": "scribble",
        "Solved bit": "lightbulb.fill",
        "Done": "flag.checkered",
        "Before room": "photo.on.rectangle",
        "Floor check": "square.grid.3x3.fill",
        "Desk reset": "desktopcomputer",
        "Closet pass": "tshirt.fill",
        "Trash run": "trash.fill",
        "Best detail": "star.fill",
        "After room": "checkmark.seal.fill",
        "Morning": "sunrise.fill",
        "Move": "figure.walk",
        "Outfit": "tshirt.fill",
        "Food": "fork.knife",
        "Little win": "trophy.fill",
        "Mirror check": "person.crop.circle",
        "Night": "moon.stars.fill",
        "Meet": "person.2.fill",
        "Walk": "figure.walk",
        "Laugh": "face.smiling.fill",
        "Side quest": "map.fill",
        "Favorite clip": "heart.fill",
        "Bye": "hand.wave.fill",
    ]

    static func icon(forPrompt prompt: String?) -> String {
        guard let prompt else { return "video.circle.fill" }
        return promptIcons[prompt] ?? "video.circle.fill"
    }
}

/// A recorded clip labeled with its challenge day — the stitcher's input.
/// In a shared room a single day can hold several clips (one per friend), so
/// `id` is unique rather than the day number.
struct DayClip: Identifiable {
    let id: String
    let day: Int
    let url: URL
    var authorName: String?
    var label: String?
    var overlayText: String?
    var recordedAt: Date?

    init(
        day: Int,
        url: URL,
        authorName: String? = nil,
        label: String? = nil,
        overlayText: String? = nil,
        recordedAt: Date? = nil,
        key: String? = nil
    ) {
        self.day = day
        self.url = url
        self.authorName = authorName
        self.label = label
        self.overlayText = overlayText
        self.recordedAt = recordedAt
        self.id = key ?? "day\(day)"
    }
}

struct DayCard: Codable, Identifiable {
    let day: Int
    var clipFileName: String?
    var recordedAt: Date?
    var overlayText: String?

    var id: Int { day }

    enum Status: Equatable {
        case done      // clip recorded
        case today     // it's this day, no clip yet
        case missed    // day passed without a clip (still recordable, late)
        case locked    // future day
    }

    func status(currentDay: Int) -> Status {
        if clipFileName != nil { return .done }
        if day == currentDay { return .today }
        if day < currentDay { return .missed }
        return .locked
    }
}
