import SwiftUI


struct AvatarDot: View {
    let name: String?
    var size: CGFloat = 34
    var isPending = false
    var isYou = false
    var image: UIImage? = nil

    @AppStorage(Identity.myTintKey) private var myTintIndex = -1

    private var tint: Color { Identity.tint(for: name) }
    private var hasName: Bool { name?.isEmpty == false }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.12)
                    .opacity(isPending ? 0.58 : 1)
                    .accessibilityHidden(true)
            } else if hasName {
                Text(Identity.initial(for: name))
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(isPending ? tint : .white)
            } else {
                Image(AppSkin.mascotImageName)
                    .resizable()
                    .scaledToFill()
                    .opacity(isPending ? 0.58 : 1)
                    .accessibilityHidden(true)
            }
        }
            .frame(width: size, height: size)
            .background {
                if image != nil {
                    Circle().fill(Color.white)
                } else if isPending {
                    Circle().fill(tint.opacity(0.14))
                } else if hasName {
                    Circle().fill(tint.gradient)
                } else {
                    Circle().fill(Color.oneDayMist)
                }
            }
            .clipShape(Circle())
            .overlay {
                if isPending {
                    Circle().strokeBorder(
                        tint.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
            }
            .overlay {
                Circle().strokeBorder(.white, lineWidth: size * 0.06)
            }
            .overlay {
                if isYou {
                    Circle()
                        .strokeBorder(Color.oneDayMint, lineWidth: size * 0.07)
                        .padding(-size * 0.07)
                }
            }
    }
}

private struct AvatarOverflowDot: View {
    let count: Int
    var size: CGFloat = 34

    var body: some View {
        Text("+\(count)")
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(OneDay.brandText)
            .frame(width: size, height: size)
            .background(OneDay.surfaceSoft, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: size * 0.06))
    }
}

struct AvatarStack: View {
    let names: [String]
    var maxShown: Int = 4
    var size: CGFloat = 30
    var pending: Set<String> = []
    var you: String?
    var images: [String: UIImage] = [:]

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(maxShown).enumerated()), id: \.offset) { _, name in
                AvatarDot(
                    name: name,
                    size: size,
                    isPending: pending.contains(name),
                    isYou: name == you,
                    image: images[name])
            }
            if names.count > maxShown {
                AvatarOverflowDot(count: names.count - maxShown, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenNames))
    }

    private var spokenNames: String {
        names.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct RoomAvatarCluster: View {
    let members: [(id: String, name: String)]
    var you: String?
    var images: [String: UIImage] = [:]

    private var displayedMembers: [(id: String, name: String)] {
        members.isEmpty ? [("loading", "")] : members
    }

    var body: some View {
        let members = displayedMembers
        let layout = RoomAvatarLayout(memberCount: members.count)
        ZStack(alignment: .topLeading) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                AvatarDot(name: member.name, size: layout.diameter, isYou: member.id == you, image: images[member.id])
                    .position(layout.centers[index])
            }
        }
        .frame(width: RoomAvatarLayout.width, height: RoomAvatarLayout.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([Strings.memberCount(members.count)] + members.map {
            $0.name.isEmpty ? Strings.defaultMemberName : $0.name
        }).joined(separator: ", "))
    }
}
