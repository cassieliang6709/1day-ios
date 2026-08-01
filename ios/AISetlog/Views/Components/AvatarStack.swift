import SwiftUI

/// Who's in the story. Identity color comes from `Identity`, so a person is
/// the same color in the avatar, the timeline node, and their clip's byline.

/// A single person as a colored initial. A pending dot (their moment isn't in
/// yet) hollows out instead of disappearing — the group is always visible,
/// what changes is who has filmed.
struct AvatarDot: View {
    let name: String?
    var size: CGFloat = 34
    var isPending = false
    /// Draws a bright ring around the dot — used for "this is you".
    var isYou = false

    private var tint: Color { Identity.tint(for: name) }

    var body: some View {
        Text(Identity.initial(for: name))
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(isPending ? tint : .white)
            .frame(width: size, height: size)
            .background {
                if isPending {
                    Circle().fill(tint.opacity(0.14))
                } else {
                    Circle().fill(tint.gradient)
                }
            }
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

/// The "+N" overflow bubble at the end of a stack.
private struct AvatarOverflowDot: View {
    let count: Int
    var size: CGFloat = 34

    var body: some View {
        Text("+\(count)")
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(Color.oneDayBlue)
            .frame(width: size, height: size)
            .background(OneDay.surfaceSoft, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: size * 0.06))
    }
}

/// Overlapping identity circles for everyone in a room, capped with "+N".
struct AvatarStack: View {
    let names: [String]
    var maxShown: Int = 4
    var size: CGFloat = 30
    /// Names still waiting to contribute — drawn hollow.
    var pending: Set<String> = []

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(maxShown).enumerated()), id: \.offset) { _, name in
                AvatarDot(name: name, size: size, isPending: pending.contains(name))
            }
            if names.count > maxShown {
                AvatarOverflowDot(count: names.count - maxShown, size: size)
            }
        }
    }
}

/// Avatar over a name — the roster row at the top of a shared timeline.
struct AvatarBadge: View {
    let name: String
    var isYou = false
    var isPending = false
    var size: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            AvatarDot(name: name, size: size, isPending: isPending, isYou: isYou)
            Text(name)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(isPending ? OneDay.inkFaint : OneDay.ink)
                .lineLimit(1)
                .frame(maxWidth: size + 18)
        }
    }
}
