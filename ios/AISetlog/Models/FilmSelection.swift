import Foundation

/// Which takes go into a room's film, and which of them stand still.
///
/// Stored as what was taken *out*, not what was kept: a take somebody films
/// after you last picked is in the film until you say otherwise, and so is
/// everything from a person you never touched. Leaving a person out is its own
/// field rather than all of their takes, so their next take stays out too.
///
/// Kept on this phone only (`FilmSelectionStore`). It is how you want your
/// copy of the film cut, not something the room agrees on.
struct FilmSelection: Codable, Equatable {
    /// People left out entirely, by `person(of:)`.
    var leftOutPeople: Set<String> = []
    /// Single takes left out, by `DayClip.id`.
    var leftOutClips: Set<String> = []
    /// Takes held on one frame: `DayClip.id` → seconds into the take.
    var freezes: [String: Double] = [:]

    /// Who filmed a take, as the key this selection files them under. The
    /// account id when there is one, so two people with one name stay apart.
    static func person(of clip: DayClip) -> String {
        clip.authorID ?? clip.authorName ?? ""
    }

    func includes(person key: String) -> Bool { !leftOutPeople.contains(key) }

    func includes(_ clip: DayClip) -> Bool {
        includes(person: Self.person(of: clip)) && !leftOutClips.contains(clip.id)
    }

    /// The takes that go into the film, in their order.
    ///
    /// A selection that leaves nothing gives every take back instead. The
    /// sheet won't apply one, but the room can change under a saved one —
    /// the only person you kept deletes their takes — and a film page that
    /// can't make a film has no way back to the sheet that would fix it.
    func applied(to clips: [DayClip]) -> [DayClip] {
        let kept = clips.filter(includes)
        return kept.isEmpty ? clips : kept
    }

    /// `freezes`, narrowed to takes that are actually in the film.
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

    /// Nil lets the take play again.
    mutating func set(freeze seconds: Double?, for id: String) {
        freezes[id] = seconds.map { max($0, 0) }
    }

    /// The same choices, minus anything about takes no longer in the room.
    /// People are left alone: somebody with no takes today may film tomorrow.
    func pruned(to clips: [DayClip]) -> FilmSelection {
        let ids = Set(clips.map(\.id))
        var out = self
        out.leftOutClips = leftOutClips.filter(ids.contains)
        out.freezes = freezes.filter { ids.contains($0.key) }
        return out
    }

    /// One string that changes whenever the film would. Sorted by hand:
    /// `Set` and `Dictionary` have no order of their own to encode in.
    var cacheKey: String {
        let people = leftOutPeople.sorted().joined(separator: ",")
        let clips = leftOutClips.sorted().joined(separator: ",")
        let held = freezes.sorted { $0.key < $1.key }
            .map { "\($0.key)@\(String(format: "%.3f", $0.value))" }
            .joined(separator: ",")
        return "p[\(people)]c[\(clips)]f[\(held)]"
    }
}

/// One person in a room's film, with their takes in film order.
struct FilmPerson: Identifiable {
    /// `FilmSelection.person(of:)`.
    let id: String
    let name: String?
    let clips: [DayClip]

    /// Everybody with a take, in the order they first appear in the film.
    /// Only people who filmed something: a person with no takes has nothing
    /// to pick.
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

/// Where a room's `FilmSelection` lives: this phone's defaults, one entry per
/// story. Not synced — see `FilmSelection`.
enum FilmSelectionStore {
    static func key(for story: UUID) -> String { "film.selection.v1.\(story.uuidString)" }

    static func load(for story: UUID, defaults: UserDefaults = .standard) -> FilmSelection {
        guard let data = defaults.data(forKey: key(for: story)),
              let selection = try? JSONDecoder().decode(FilmSelection.self, from: data)
        else { return FilmSelection() }
        return selection
    }

    static func save(_ selection: FilmSelection, for story: UUID, defaults: UserDefaults = .standard) {
        // An untouched selection is the default; don't leave a row behind for it.
        guard selection != FilmSelection() else {
            defaults.removeObject(forKey: key(for: story))
            return
        }
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: key(for: story))
    }
}
