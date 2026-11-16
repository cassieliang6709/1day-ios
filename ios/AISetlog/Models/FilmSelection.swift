import Foundation

struct FilmSelection: Codable, Equatable {
    var leftOutPeople: Set<String> = []
    var leftOutClips: Set<String> = []
    var freezes: [String: Double] = [:]
    var dayOrder: [Int] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leftOutPeople = try c.decodeIfPresent(Set<String>.self, forKey: .leftOutPeople) ?? []
        leftOutClips = try c.decodeIfPresent(Set<String>.self, forKey: .leftOutClips) ?? []
        freezes = try c.decodeIfPresent([String: Double].self, forKey: .freezes) ?? [:]
        dayOrder = try c.decodeIfPresent([Int].self, forKey: .dayOrder) ?? []
    }

    func orderedDays(_ days: some Sequence<Int>) -> [Int] {
        let unique = Array(Set(days))
        let rank = Dictionary(dayOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return unique.sorted { (rank[$0] ?? Int.max, $0) < (rank[$1] ?? Int.max, $1) }
    }

    static func person(of clip: DayClip) -> String {
        clip.authorID ?? clip.authorName ?? ""
    }

    func includes(person key: String) -> Bool { !leftOutPeople.contains(key) }

    func includes(_ clip: DayClip) -> Bool {
        includes(person: Self.person(of: clip)) && !leftOutClips.contains(clip.id)
    }

    func applied(to clips: [DayClip]) -> [DayClip] {
        let kept = clips.filter(includes)
        return kept.isEmpty ? clips : kept
    }

    func freezeFrames(for clips: [DayClip]) -> [String: Double] {
        let ids = Set(applied(to: clips).map(\.id))
        return freezes.filter { ids.contains($0.key) }
    }

    func freeze(of clipID: String) -> Double? { freezes[clipID] }

    mutating func set(person key: String, included: Bool) {
        if included { leftOutPeople.remove(key) } else { leftOutPeople.insert(key) }
    }

    mutating func set(clip id: String, included: Bool) {
        if included { leftOutClips.remove(id) } else { leftOutClips.insert(id) }
    }

    mutating func set(freeze seconds: Double?, for id: String) {
        freezes[id] = seconds.map { max($0, 0) }
    }

    func pruned(to clips: [DayClip]) -> FilmSelection {
        let ids = Set(clips.map(\.id))
        var out = self
        out.leftOutClips = leftOutClips.filter(ids.contains)
        out.freezes = freezes.filter { ids.contains($0.key) }
        let days = Set(clips.map(\.day))
        out.dayOrder = dayOrder.filter(days.contains)
        return out
    }

    var cacheKey: String {
        let people = leftOutPeople.sorted().joined(separator: ",")
        let clips = leftOutClips.sorted().joined(separator: ",")
        let held = freezes.sorted { $0.key < $1.key }
            .map { "\($0.key)@\(String(format: "%.3f", $0.value))" }
            .joined(separator: ",")
        let order = dayOrder.map(String.init).joined(separator: ",")
        return "p[\(people)]c[\(clips)]f[\(held)]o[\(order)]"
    }
}

struct FilmPerson: Identifiable {
    let id: String
    let name: String?
    let clips: [DayClip]

    static func people(in clips: [DayClip]) -> [FilmPerson] {
        var order: [String] = []
        var byKey: [String: [DayClip]] = [:]
        for clip in clips {
            let key = FilmSelection.person(of: clip)
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(clip)
        }
        return order.map { key in
            let takes = byKey[key] ?? []
            return FilmPerson(
                id: key,
                name: takes.lazy.compactMap(\.authorName).first { !$0.isEmpty },
                clips: takes)
        }
    }
}

enum FilmSelectionStore {
    static func key(for story: UUID) -> String { "film.selection.v1.\(story.uuidString)" }

    static func load(for story: UUID, defaults: UserDefaults = .standard) -> FilmSelection {
        guard let data = defaults.data(forKey: key(for: story)),
              let selection = try? JSONDecoder().decode(FilmSelection.self, from: data)
        else { return FilmSelection() }
        return selection
    }

    static func save(_ selection: FilmSelection, for story: UUID, defaults: UserDefaults = .standard) {
        guard selection != FilmSelection() else {
            defaults.removeObject(forKey: key(for: story))
            return
        }
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: key(for: story))
    }
}
