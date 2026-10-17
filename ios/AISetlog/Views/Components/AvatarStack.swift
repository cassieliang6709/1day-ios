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

    /// Bound, not read: picking your own colour in Settings has to repaint
    /// every avatar of you on the screen behind it — the header, your clips'
    /// bylines, your dot in the roster. `Identity` reads the same key, so
    /// observing it here is what makes all of them update at once.
    @AppStorage(Identity.myTintKey) private var myTintIndex = -1

    private var tint: Color { Identity.tint(for: name) }
    private var hasName: Bool { name?.isEmpty == false }

    var body: some View {
        Group {
            if hasName {
                // Fixed, relative to the dot: an initial that grew with
                // Dynamic Type would burst out of a circle that doesn't.
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
                if isPending {
                    Circle().fill(tint.opacity(0.14))
                } else if hasName {
                    Circle().fill(tint.gradient)
                } else {
                    // The mascot brings its own colour; behind it, the skin's
                    // soft fill rather than an identity hue nobody chose.
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

/// The "+N" overflow bubble at the end of a stack.
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

/// Overlapping identity circles for everyone in a room, capped with "+N".
struct AvatarStack: View {
    let names: [String]
    var maxShown: Int = 4
    var size: CGFloat = 30
    /// Names still waiting to contribute — drawn hollow.
    var pending: Set<String> = []
    /// Which of these names is mine, so a roster can ring my own face. Nil
    /// where the stack is a list of other people and pointing at one of them
    /// would be pointing at nobody.
    var you: String?

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(maxShown).enumerated()), id: \.offset) { _, name in
                AvatarDot(
                    name: name,
                    size: size,
                    isPending: pending.contains(name),
                    isYou: name == you)
            }
            if names.count > maxShown {
                AvatarOverflowDot(count: names.count - maxShown, size: size)
            }
        }
        // One element reading the names. Left alone, VoiceOver walked the
        // dots and read each initial as a letter — "A, L, plus two" — and
        // skipped the mascot faces of unnamed people entirely.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenNames))
    }

    private var spokenNames: String {
        names.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
