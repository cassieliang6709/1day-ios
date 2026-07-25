import SwiftUI

/// Social pieces of `ClipPreviewView` — emoji reactions and the comment
/// thread. Stateless: the parent owns the store calls.

/// Row of toggleable emoji reactions; the viewer's own reactions light up.
struct ReactionBar: View {
    let reactions: [ClipReaction]
    let myID: String
    let onToggle: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ClipReaction.palette, id: \.self) { emoji in
                let count = reactions.filter { $0.emoji == emoji }.count
                let mine = reactions.contains { $0.emoji == emoji && $0.authorID == myID }
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        onToggle(emoji)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(emoji).font(.system(size: 18))
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption.bold())
                                .foregroundStyle(mine ? Color.oneDayBlue : .secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(mine ? Color.oneDaySky.opacity(0.5) : Color.gray.opacity(0.12)))
                    .overlay(
                        Capsule().strokeBorder(
                            mine ? Color.oneDayBlue.opacity(0.6) : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: mine)
            }
        }
    }
}

/// The comment list, or a "be the first" placeholder when empty.
struct CommentsSection: View {
    let comments: [ClipComment]
    let myID: String
    let onDelete: (ClipComment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(comments.isEmpty ? Strings.comments : Strings.commentsCount(comments.count))
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if comments.isEmpty {
                Text(Strings.firstComment)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
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

/// Bottom input bar; owns its draft text and focus, reports sends upward.
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
                    .foregroundStyle(canSend ? Color.oneDayBlue : Color.gray.opacity(0.4))
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
