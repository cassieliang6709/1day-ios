import Foundation
import UIKit

struct MyRoomProfile: Equatable {
    var avatarURL: URL?
    var avatarVersion: Date?
    var mood: Mood?
    var moodAt: Date?

    @MainActor
    static func make(avatar: AvatarStore, today: MoodEntry?) -> MyRoomProfile {
        MyRoomProfile(
            avatarURL: avatar.savedFileURL, avatarVersion: avatar.version,
            mood: today?.mood, moodAt: today?.updatedAt)
    }

    func signature(displayName: String) -> String {
        let day = moodAt.map { MoodDay.key(for: $0) } ?? "-"
        return [displayName, avatarSignature, mood?.rawValue ?? "-", day].joined(separator: "|")
    }

    private var avatarSignature: String {
        avatarVersion.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
    }

    func hasSameAvatar(asSignature signature: String?) -> Bool {
        guard let signature else { return false }
        let parts = signature.split(separator: "|", omittingEmptySubsequences: false)
        return parts.count == 4 && parts[1] == avatarSignature
    }
}

struct MemberProfile: Equatable {
    var avatarURL: URL?
    var mood: Mood?

    static func todaysMood(kind: String?, day: Date?, now: Date = .now,
                           calendar: Calendar = .current) -> Mood? {
        guard let kind, let day, calendar.isDate(day, inSameDayAs: now) else { return nil }
        return Mood(rawValue: kind)
    }
}

extension ChallengeStore {
    @MainActor
    func publishMyProfileToAllRooms() async {
        for code in challenges.filter(\.isShared).compactMap(\.roomCode) {
            await publishMyProfile(toRoom: code)
        }
    }

    @MainActor
    func publishMyProfile(toRoom code: String) async {
        guard effects.allowsCloudRoomManagement, let me = account?.account,
              let profile = myRoomProfile()
        else { return }
        guard profile.avatarURL != nil || profile.mood != nil else { return }
        let sameAvatar = profile.hasSameAvatar(asSignature: roomSync.publishedProfileSignature(code: code))
        let write = CloudKitService.MemberProfileWrite(
            code: code, authorID: me.id, displayName: me.displayName,
            avatarURL: sameAvatar ? nil : profile.avatarURL,
            moodKind: profile.mood?.rawValue, moodDay: profile.moodAt)
        await roomSync.publishProfile(write, signature: profile.signature(displayName: me.displayName))
    }

    func memberProfiles(for challengeID: UUID, now: Date = .now) -> [String: MemberProfile] {
        guard let code = challenge(challengeID)?.roomCode else { return [:] }
        return (roomSync.remoteMembers[code] ?? [:]).mapValues {
            MemberProfile(
                avatarURL: $0.avatarURL,
                mood: MemberProfile.todaysMood(kind: $0.moodKind, day: $0.moodDay, now: now))
        }
    }
}

extension ChallengeStore {
    @MainActor
    func memberAvatarsByID(for challengeID: UUID) -> [String: UIImage] {
        let profiles = memberProfiles(for: challengeID)
        let myID = account?.account?.id
        var out: [String: UIImage] = [:]
        for member in members(for: challengeID) {
            let image = member.id == myID
                ? AvatarStore.shared.image
                : AvatarImageCache.image(at: profiles[member.id]?.avatarURL)
            if let image { out[member.id] = image }
        }
        return out
    }
}
