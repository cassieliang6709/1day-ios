import SwiftUI


struct ReactionBar: View {
    let reactions: [ClipReaction]
    let myID: String
    let onToggle: (String) -> Void

    @State private var picking = false
    @AppStorage(ClipReactionRecents.storageKey) private var recentsData = ""

    private var recents: [String] {
        recentsData.split(separator: "\n").map(String.init)
    }

    struct Tally: Identifiable {
        let emoji: String
        let count: Int
        let mine: Bool
        var id: String { emoji }
    }

    private var present: [Tally] {
        let groups: [String: [ClipReaction]] = Dictionary(grouping: reactions, by: \.emoji)
        let tallies: [Tally] = groups.map { emoji, group in
            Tally(
                emoji: emoji,
                count: group.count,
                mine: group.contains { $0.authorID == myID })
        }
        return tallies.sorted { left, right in
            left.count == right.count ? left.emoji < right.emoji : left.count > right.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                ForEach(present) { item in
                    chip(item.emoji, count: item.count, mine: item.mine)
                }
                addButton
                Spacer(minLength: 0)
            }
            if picking { picker }
        }
        .animation(OneDay.Motion.snap, value: picking)
        .animation(OneDay.Motion.snap, value: present.count)
    }

    private func chip(_ emoji: String, count: Int, mine: Bool) -> some View {
        Button {
            toggle(emoji)
        } label: {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 15))
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(mine ? Color.oneDayBrand : OneDay.inkSoft)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                mine ? Color.oneDayBrand.opacity(0.13) : OneDay.surfaceSoft.opacity(0.9),
                in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    mine ? Color.oneDayBrand.opacity(0.45) : OneDay.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: mine)
        .accessibilityLabel("\(emoji) \(count)")
    }

    private var addButton: some View {
        Button {
            picking.toggle()
        } label: {
            Image(systemName: picking ? "xmark" : "face.smiling")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OneDay.inkSoft)
                .frame(width: 30, height: 27)
                .background(OneDay.surfaceSoft.opacity(0.9), in: Capsule())
                .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.addReaction)
        .accessibilityIdentifier("add-reaction")
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(ClipReactionRecents.suggestions(recents: recents), id: \.self) { emoji in
                    Button { toggle(emoji) } label: {
                        Text(emoji)
                            .font(.system(size: 19))
                            .frame(width: 33, height: 33)
                            .background(OneDay.surfaceSoft.opacity(0.85), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            AnyEmojiField { toggle($0) }
        }
        .padding(8)
        .background(OneDay.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(OneDay.hairline, lineWidth: 1)
        }
        .transition(.scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity))
    }

    private func toggle(_ emoji: String) {
        recentsData = ClipReactionRecents
            .adding(emoji, to: recents)
            .joined(separator: "\n")
        picking = false
        onToggle(emoji)
    }
}

private struct AnyEmojiField: View {
    let onPick: (String) -> Void

    @State private var typed = ""

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "keyboard")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OneDay.inkFaint)
            TextField(Strings.anyEmojiPlaceholder, text: $typed)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .tint(Color.oneDayBrand)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("any-emoji")
                .onChange(of: typed) { _, new in
                    guard let first = new.first else { return }
                    typed = ""
                    guard String(first).containsEmoji else { return }
                    onPick(String(first))
                }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(OneDay.surfaceSoft.opacity(0.7), in: Capsule())
    }
}

extension String {
    var containsEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value > 0x238C }
    }
}

struct CommentsSection: View {
    let comments: [ClipComment]
    let myID: String
    let onDelete: (ClipComment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !comments.isEmpty {
                ForEach(comments) { comment in
                    CommentRow(comment: comment, isMine: comment.authorID == myID) {
                        onDelete(comment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CommentRow: View {
    let comment: ClipComment
    let isMine: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Identity.initial(for: comment.authorName))
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Identity.tint(for: comment.authorName).gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.footnote.bold())
                    Text(comment.createdAt, format: .relative(presentation: .numeric))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(comment.text)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if isMine {
                Button(Strings.delete, systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }
}

struct CommentInputBar: View {
    let onSend: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(Strings.addComment, text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.gray.opacity(0.14)))
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.oneDayBrand : Color.gray.opacity(0.4))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        guard canSend else { return }
        onSend(draft)
        draft = ""
        focused = false
    }
}
