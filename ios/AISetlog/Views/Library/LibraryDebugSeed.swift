#if DEBUG
import Foundation

@MainActor
enum LibraryDebugSeed {
    private static let doneKey = "debugSeedLibrary.done"

    static func runIfAsked(store: ChallengeStore, drafts: ClipDraftStore, moods: MoodStore?) {
        #if targetEnvironment(simulator)
        seedRoomPreviewsIfAsked(store: store)
        #endif
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "debugSeedLibrary"), !defaults.bool(forKey: doneKey),
              let sample = Bundle.main.url(forResource: "sample-film", withExtension: "mp4")
        else { return }
        defaults.set(true, forKey: doneKey)

        let day = store.createQuickStart()
        for slot in 1...3 { store.saveClip(from: copy(sample), day: slot, challengeID: day.id) }
        let week = store.create(
            title: AppLanguage.effective.resolved == .chinese ? "7 天早起" : "Early mornings", mode: .sevenDay)
        store.saveClip(from: copy(sample), day: 1, challengeID: week.id)

        for daysAgo in [1, 1, 3] {
            let at = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            _ = try? drafts.keep(tempURL: copy(sample), orientation: .portrait, recordedAt: at)
        }
        moods?.setMood(.happy)
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) {
            moods?.setMood(.calm, on: yesterday)
        }
    }

    #if targetEnvironment(simulator)
    private static func seedRoomPreviewsIfAsked(store: ChallengeStore) {
        guard UserDefaults.standard.bool(forKey: "debugSeedRoomPreviews"),
              let sample = Bundle.main.url(forResource: "sample-film", withExtension: "mp4") else { return }
        let names = ["Cassie", "尼尼", "Ana", "Bo", "Cy", "Di"]
        let titles = ["周末放映室", "今天的碎片", "家里的日常", "出门走走", "小小片场"]
        let captions = ["下班路上的晚霞", "今天也拍了一点点", "晚饭后一起散步", "天气好，去河边走走", "把日常拍成小片"]
        for count in 2...6 {
            let code = "UI000\(count)"
            guard store.roomSync.remoteClips[code] == nil else { continue }
            if !store.challenges.contains(where: { $0.roomCode == code }) {
                store.challenges.append(Challenge(
                    id: UUID(), title: titles[count - 2], startDate: .now,
                    cards: [DayCard(day: 1)], roomCode: code, ownerName: names[0], ownerID: "preview-0"))
            }
            let members = names.prefix(count).enumerated().map { index, name in
                CloudKitService.RemoteMember(userID: "preview-\(index)", displayName: name,
                    avatarURL: nil, moodKind: nil, moodDay: nil)
            }
            store.roomSync.remoteMembers[code] = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0) })
            let pastAuthor = count > 2 ? 2 : 1
            store.roomSync.remoteClips[code] = [
                .init(
                    id: "\(code)-clip", day: 1, authorID: "preview-1", authorName: names[1],
                    recordedAt: Date.now.addingTimeInterval(Double(-count * 60)), localURL: sample,
                    overlayText: captions[count - 2]),
                .init(
                    id: "\(code)-clip-1", day: 1, authorID: "preview-1", authorName: names[1],
                    recordedAt: Date.now.addingTimeInterval(-86_400), localURL: sample,
                    overlayText: captions[(count - 1) % captions.count]),
                .init(
                    id: "\(code)-clip-3", day: 1, authorID: "preview-\(pastAuthor)", authorName: names[pastAuthor],
                    recordedAt: Date.now.addingTimeInterval(-3 * 86_400), localURL: sample,
                    overlayText: captions[count % captions.count]),
            ]
            if count > 2 {
                store.roomSync.remoteReactions[code] = [.init(
                    day: 1, emoji: "😂", authorID: "preview-2", authorName: names[2],
                    targetAuthorID: "preview-1", createdAt: .now)]
            }
        }
    }
    #endif

    private static func copy(_ url: URL) -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        try? FileManager.default.copyItem(at: url, to: temp)
        return temp
    }
}
#endif
