import SwiftUI

/// Room members' avatars and today's moods, keyed by user ID. Set by the room
/// page (`ChallengeStore.memberProfiles(for:)`) and read by every `MemberFace`
/// under it, so a view that draws a person doesn't need new parameters.
private struct MemberProfilesKey: EnvironmentKey {
    static let defaultValue: [String: MemberProfile] = [:]
}

extension EnvironmentValues {
    var memberProfiles: [String: MemberProfile] {
        get { self[MemberProfilesKey.self] }
        set { self[MemberProfilesKey.self] = newValue }
    }
}

/// One person in a room: their avatar (or their initial) and, if they picked
/// one today, their mood's face pinned to the corner.
///
/// For me it reads this phone — `AvatarStore` and `MoodStore` — so my own face
/// and mood show the moment I set them, without waiting for CloudKit. For
/// anyone else it reads `memberProfiles`.
struct MemberFace: View {
    let id: String?
    let name: String?
    var size: CGFloat = 34
    var isPending = false
    var isYou = false
    /// Whether to pin today's mood. Off where a face is just a byline.
    var showsMood = true

    @Environment(\.memberProfiles) private var profiles
    /// Optional: a preview or a test host without a `MoodStore` just shows no mood.
    @Environment(MoodStore.self) private var moods: MoodStore?
    @Environment(AccountStore.self) private var account: AccountStore?
    private var avatars: AvatarStore { AvatarStore.shared }

    /// Me, whether or not this face is drawn with the "you" ring: a film's
    /// people row lists me by my author ID like everyone else.
    private var isMe: Bool {
        isYou || (id != nil && (id == account?.account?.id || id == RoomProgress.soloAuthorID))
    }

    private var image: UIImage? {
        if isMe { return avatars.image }
        return AvatarImageCache.image(at: id.flatMap { profiles[$0]?.avatarURL })
    }

    private var mood: Mood? {
        guard showsMood else { return nil }
        if isMe { return moods?.today?.mood }
        return id.flatMap { profiles[$0]?.mood }
    }

    var body: some View {
        AvatarDot(name: name, size: size, isPending: isPending, isYou: isYou, image: image)
            .overlay(alignment: .bottomTrailing) {
                if let mood {
                    MoodBadge(mood: mood, size: max(size * 0.5, 16))
                        .offset(x: size * 0.14, y: size * 0.1)
                }
            }
            // Not an element of its own, and no identifier: a face usually
            // sits inside a button (the film's people row, a room frame's
            // name) whose identifier UI tests look up, and an element here
            // would take that over. The label still says the mood.
            .accessibilityLabel(Text(spoken))
    }

    private var spoken: String {
        let who = isYou ? Strings.youLabel : (name ?? "")
        guard let mood else { return who }
        return Strings.memberMoodAccessibility(name: who, mood: mood.label)
    }
}

/// Today's mood face, in a small white disc so it reads on any avatar.
struct MoodBadge: View {
    let mood: Mood
    var size: CGFloat = 18

    var body: some View {
        Image(mood.imageName)
            .resizable()
            .scaledToFit()
            .padding(size * 0.08)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}
