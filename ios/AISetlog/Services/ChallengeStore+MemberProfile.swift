import Foundation
import UIKit

/// What a room shows of me beyond my name: the avatar file and today's mood.
/// Only the mood's face — the note is never in here.
struct MyRoomProfile: Equatable {
    var avatarURL: URL?
    /// When the avatar was last saved; part of what makes a change "new".
    var avatarVersion: Date?
    var mood: Mood?
    /// When today's mood was picked (`MoodEntry.updatedAt`). Nil without one.
    var moodAt: Date?

    /// Today's entry, or nothing: yesterday's mood is not today's to show.
    @MainActor
    static func make(avatar: AvatarStore, today: MoodEntry?) -> MyRoomProfile {
        MyRoomProfile(
            avatarURL: avatar.savedFileURL, avatarVersion: avatar.version,
            mood: today?.mood, moodAt: today?.updatedAt)
    }

    /// Same signature, nothing new to send.
    func signature(displayName: String) -> String {
        let day = moodAt.map { MoodDay.key(for: $0) } ?? "-"
        return [displayName, avatarSignature, mood?.rawValue ?? "-", day].joined(separator: "|")
    }

    private var avatarSignature: String {
        avatarVersion.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
    }

    /// Whether the avatar in `signature` is the one this profile has — then a
    /// mood change doesn't upload the same picture again.
    func hasSameAvatar(asSignature signature: String?) -> Bool {
        guard let signature else { return false }
        let parts = signature.split(separator: "|", omittingEmptySubsequences: false)
        return parts.count == 4 && parts[1] == avatarSignature
    }
}

/// A room member's face and mood, ready for `MemberFace`.
struct MemberProfile: Equatable {
    var avatarURL: URL?
    var mood: Mood?

    /// A mood shows only on the day it was picked, in the viewer's calendar.
    static func todaysMood(kind: String?, day: Date?, now: Date = .now,
                           calendar: Calendar = .current) -> Mood? {
        guard let kind, let day, calendar.isDate(day, inSameDayAs: now) else { return nil }
        return Mood(rawValue: kind)
    }
}

extension ChallengeStore {
    /// Brings my `Member` record in every shared room up to date with my
    /// avatar and today's mood. Called when either changes and when the app
    /// comes to the front; rooms that already have this exact version are
    /// skipped, and a failed write (before the CloudKit schema is deployed,
    /// every write fails) is only logged.
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
        // Nothing to say yet: no avatar and no mood today. The join already
        // wrote the plain record.
        guard profile.avatarURL != nil || profile.mood != nil else { return }
        let sameAvatar = profile.hasSameAvatar(asSignature: roomSync.publishedProfileSignature(code: code))
        let write = CloudKitService.MemberProfileWrite(
            code: code, authorID: me.id, displayName: me.displayName,
            avatarURL: sameAvatar ? nil : profile.avatarURL,
            moodKind: profile.mood?.rawValue, moodDay: profile.moodAt)
        await roomSync.publishProfile(write, signature: profile.signature(displayName: me.displayName))
    }

    /// Everyone in a room I have a `Member` record for, keyed by user ID.
    /// Missing people simply show their initial, as before.
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
    /// Avatars by member name, for views that only know names (the 朋友
    /// tab's faces-as-cover stack). Mine comes from this phone.
    @MainActor
    func memberAvatars(for challengeID: UUID) -> [String: UIImage] {
        let profiles = memberProfiles(for: challengeID)
        let myID = account?.account?.id
        var out: [String: UIImage] = [:]
        for member in members(for: challengeID) {
            let image = member.id == myID
                ? AvatarStore.shared.image
                : AvatarImageCache.image(at: profiles[member.id]?.avatarURL)
            if let image { out[member.name] = image }
        }
        return out
    }
}
