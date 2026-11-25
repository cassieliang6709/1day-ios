import Foundation

enum RoomFeed {
    struct Column: Identifiable {
        let id: String
        let name: String
        let isMine: Bool
        let clips: [DayClip]
    }

    static func columns(
        clips: [DayClip],
        members: [(id: String, name: String)],
        myID: String
    ) -> [Column] {
        func key(_ clip: DayClip) -> String {
            if clip.authorID == myID || clip.authorID == RoomProgress.soloAuthorID { return myID }
            return clip.authorID ?? clip.authorName ?? clip.id
        }
        let byAuthor = Dictionary(grouping: clips, by: key).mapValues { group in
            group.sorted { ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }
        }

        var seen: Set<String> = [myID]
        var out = [Column(id: myID, name: Strings.youLabel, isMine: true, clips: byAuthor[myID] ?? [])]

        let others = members
            .filter { $0.id != myID && $0.id != RoomProgress.soloAuthorID }
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        for member in others where seen.insert(member.id).inserted {
            out.append(Column(id: member.id, name: member.name, isMine: false,
                              clips: byAuthor[member.id] ?? []))
        }
        let strangers = byAuthor
            .filter { !seen.contains($0.key) }
            .sorted {
                ($0.value.first?.recordedAt ?? .distantPast, $0.key)
                    > ($1.value.first?.recordedAt ?? .distantPast, $1.key)
            }
        for (authorKey, theirs) in strangers {
            out.append(Column(id: authorKey, name: theirs.first?.authorName ?? "",
                              isMine: false, clips: theirs))
        }
        return out
    }
}

extension FormatStyle where Self == Date.VerbatimFormatStyle {
    static var roomClock: Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: .current,
            calendar: Calendar(identifier: .gregorian))
    }
}
