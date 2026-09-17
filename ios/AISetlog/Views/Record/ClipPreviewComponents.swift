import SwiftUI

/// Social pieces of `ClipPreviewView` — emoji reactions and the comment
/// thread. Stateless: the parent owns the store calls.

/// What people have left on this clip, and one button to add to it.
///
/// It used to draw all six of `ClipReaction.palette` as always-on pills —
/// six dark capsules across a clip nobody had reacted to, and the only six
/// emoji the app would ever accept. Now it shows *what is there*: one light
/// chip per emoji with its count, yours outlined, and a single `+` that opens
/// a picker whose first row is the emoji you actually use.
///
/// Mounted inside the moment card on a white surface, so the untouched state
/// is light glass rather than the dark glass it needed when it floated over
/// the footage.
struct ReactionBar: View {
    let reactions: [ClipReaction]
    let myID: String
    let onToggle: (String) -> Void

    @State private var picking = false
    @AppStorage(ClipReactionRecents.storageKey) private var recentsData = ""

    /// `@AppStorage` can't hold an array, and this list is short enough that a
    /// separator-joined string beats a JSON round trip. Emoji never contain a
    /// newline, so it can't be ambiguous.
    private var recents: [String] {
        recentsData.split(separator: "\n").map(String.init)
    }

    /// One row entry per distinct emoji. A named type rather than a tuple:
    /// grouping, mapping and sorting tuples in one expression is what the type
    /// checker gives up on.
    struct Tally: Identifiable {
        let emoji: String
        let count: Int
        let mine: Bool
        var id: String { emoji }
    }

    /// Distinct emoji on this clip, most-reacted first, ties alphabetical so
    /// the row doesn't reshuffle every time somebody adds the same one.
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

    /// Your own history first, then whatever of the six defaults you haven't
    /// used, then a field for anything else — the system emoji keyboard has no
    /// API to summon on its own, so the way to reach it is a field to type in.
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

/// One character in, one reaction out.
///
/// There is no public way to present just the emoji keyboard, so this is a
/// field you tap and then switch to it yourself. It takes the first emoji
/// typed and clears immediately, which is why it has no submit button: a
/// one-character field with a Done key is two taps for one emoji.
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
                    // First grapheme only. Typing letters is a no-op rather
                    // than an error: "a" is not a reaction, and telling
                    // somebody off for it would be worse than ignoring it.
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
    /// Whether this string's first scalar is pictographic — enough to tell an
    /// emoji from a letter somebody typed by accident.
    var containsEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value > 0x238C }
    }
}

/// The comment list, or a "be the first" placeholder when empty.
///
/// No header of its own — it's presented in a sheet whose title already says
/// "Comments", and saying it twice in the same 60 points was how the sheet
/// looked when it was still an inline section under the video.
struct CommentsSection: View {
    let comments: [ClipComment]
    let myID: String
    let onDelete: (ClipComment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
