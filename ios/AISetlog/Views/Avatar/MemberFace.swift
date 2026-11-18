import SwiftUI

private struct MemberProfilesKey: EnvironmentKey {
    static let defaultValue: [String: MemberProfile] = [:]
}

extension EnvironmentValues {
    var memberProfiles: [String: MemberProfile] {
        get { self[MemberProfilesKey.self] }
        set { self[MemberProfilesKey.self] = newValue }
    }
}

struct MemberFace: View {
    let id: String?
    let name: String?
    var size: CGFloat = 34
    var isPending = false
    var isYou = false
    var showsMood = true

    @Environment(\.memberProfiles) private var profiles
    @Environment(MoodStore.self) private var moods: MoodStore?
    @Environment(AccountStore.self) private var account: AccountStore?
    private var avatars: AvatarStore { AvatarStore.shared }

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
            .accessibilityLabel(Text(spoken))
    }

    private var spoken: String {
        let who = isYou ? Strings.youLabel : (name ?? "")
        guard let mood else { return who }
        return Strings.memberMoodAccessibility(name: who, mood: mood.label)
    }
}

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
