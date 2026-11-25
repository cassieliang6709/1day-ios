import SwiftUI

struct MoodReactButton: View {
    let reactions: [ClipReaction]
    let myID: String
    var showsOthers = true
    var onCanvas = false
    let onToggle: (String) -> Void

    @State private var picking = false

    private var mine: String? {
        reactions.first { $0.authorID == myID }?.emoji
    }

    private var allMine: Set<String> {
        Set(reactions.filter { $0.authorID == myID }.map(\.emoji))
    }

    private var iconColor: Color { onCanvas ? OneDay.inkSoft : .white }

    private var bubble: Color {
        guard onCanvas else { return .clear }
        return mine == nil ? OneDay.surfaceSoft : Color.oneDayBrand
    }

    private var others: [String] {
        var seen: [String] = []
        for reaction in reactions where reaction.authorID != myID && !seen.contains(reaction.emoji) {
            seen.append(reaction.emoji)
        }
        return Array(seen.prefix(3))
    }

    var body: some View {
        HStack(spacing: OneDay.Space.xs) {
            if showsOthers {
                ForEach(others, id: \.self) { ReactionGlyph(key: $0, size: 22) }
            }
            Button { picking = true } label: {
                Group {
                    if let mine {
                        ReactionGlyph(key: mine, size: 26)
                    } else {
                        Image(systemName: "face.smiling")
                            .font(OneDay.Font.headline)
                            .foregroundStyle(iconColor)
                    }
                }
                .frame(width: 40, height: 40)
                .background(bubble, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.addReaction)
            .accessibilityIdentifier("room-clip-react")
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                HStack(spacing: OneDay.Space.xs) {
                    ForEach(ClipReaction.palette, id: \.self) { key in
                        Button {
                            picking = false
                            onToggle(key)
                        } label: {
                            ReactionGlyph(key: key, size: 34)
                                .frame(width: 48, height: 48)
                                .background(
                                    Color.oneDayBrand.opacity(allMine.contains(key) ? 0.18 : 0), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(OneDay.Space.s)
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(OneDay.Space.xs)
    }
}
