import SwiftUI

/// Looping playback of a single day's clip, with emoji reactions, a comment
/// thread, and the option to re-record. Social UI lives in
/// `ClipPreviewComponents.swift`; this file owns state and store calls.
struct ClipPreviewView: View {
    let day: Int
    var slotTitle: String?
    var authorName: String?
    var overlayText: String?
    var clipLength: Challenge.ClipLength = .tiny
    let url: URL
    let recordedAt: Date?
    var challengeID: UUID?
    let onReRecord: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var myID: String { account.account?.id ?? "local" }

    private var card: DayCard? {
        guard let challengeID else { return nil }
        return store.challenge(challengeID)?.cards.first { $0.day == day }
    }
    private var reactions: [ClipReaction] { card?.reactions ?? [] }
    private var comments: [ClipComment] {
        (card?.comments ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    clip
                        .frame(maxWidth: 340)
                        .frame(maxWidth: .infinity)

                    if challengeID != nil {
                        ReactionBar(reactions: reactions, myID: myID) { emoji in
                            if let challengeID {
                                store.toggleReaction(emoji, day: day, challengeID: challengeID)
                            }
                        }
                    }

                    if let recordedAt {
                        Text(Strings.capturedAt(recordedAt.formatted(date: .abbreviated, time: .shortened)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if challengeID != nil {
                        CommentsSection(comments: comments, myID: myID) { comment in
                            if let challengeID {
                                store.deleteComment(comment.id, day: day, challengeID: challengeID)
                            }
                        }
                    }

                    Button {
                        onReRecord()
                    } label: {
                        Label(Strings.rerecord, systemImage: "arrow.counterclockwise.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(slotTitle ?? Strings.dayN(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if challengeID != nil {
                    CommentInputBar { text in
                        if let challengeID {
                            store.addComment(text, day: day, challengeID: challengeID)
                        }
                    }
                }
            }
        }
    }

    private var clip: some View {
        ZStack {
            LoopingClipPlayer(url: url)
            MomentStampOverlay(
                name: authorName,
                momentTitle: slotTitle ?? Strings.dayN(day),
                day: day,
                mode: .review,
                timestamp: recordedAt,
                overlayText: overlayText,
                clipSeconds: clipLength.seconds
            )
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Identity.tint(for: authorName), lineWidth: 3)
        }
    }
}
