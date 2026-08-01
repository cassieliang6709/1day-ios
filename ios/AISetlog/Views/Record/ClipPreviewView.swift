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
    var targetAuthorID: String?
    let onReRecord: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account

    /// Center caption editing, right on the video — same gesture as at
    /// record time. Saved to the card on submit/focus-out.
    @State private var captionDraft = ""
    @State private var editingCaption = false
    @FocusState private var captionFocused: Bool

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var myID: String { account.account?.id ?? "local" }

    private var card: DayCard? {
        guard let challengeID else { return nil }
        return store.challenge(challengeID)?.cards.first { $0.day == day }
    }
    
    private var interactions: (reactions: [ClipReaction], comments: [ClipComment]) {
        guard let challengeID else { return ([], []) }
        return store.interactions(for: challengeID, day: day, targetAuthorID: targetAuthorID ?? myID)
    }

    private var reactions: [ClipReaction] { interactions.reactions }
    private var comments: [ClipComment] { interactions.comments }
    private var aspectRatio: CGFloat {
        guard let challengeID else { return 9 / 16 }
        return store.challenge(challengeID)?.resolvedOrientation == .landscape ? 16 / 9 : 9 / 16
    }
    /// Prefer the live card's caption so edits show immediately; fall back to
    /// the value passed in (used when there's no challenge context).
    private var liveOverlayText: String? { card?.overlayText ?? overlayText }
    private var localizedMomentTitle: String {
        slotTitle.map { MomentCatalog.localize($0) } ?? Strings.dayN(day)
    }
    private var displayLocale: Locale {
        Locale(identifier: appLanguage.resolved.localeCode)
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
                                store.toggleReaction(emoji, day: day, challengeID: challengeID, targetAuthorID: targetAuthorID ?? myID)
                            }
                        }
                    }

                    if let recordedAt {
                        Text(Strings.capturedAt(recordedAt.formatted(
                            .dateTime
                                .year()
                                .month(.abbreviated)
                                .day()
                                .hour()
                                .minute()
                                .locale(displayLocale)
                        )))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if challengeID != nil {
                        CommentsSection(comments: comments, myID: myID) { comment in
                            if let challengeID {
                                store.deleteComment(comment.id, day: day, challengeID: challengeID, targetAuthorID: targetAuthorID ?? myID)
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
            .navigationTitle(localizedMomentTitle)
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
                            store.addComment(text, day: day, challengeID: challengeID, targetAuthorID: targetAuthorID ?? myID)
                        }
                    }
                }
            }
        }
    }

    private var clip: some View {
        ZStack {
            LoopingClipPlayer(url: url, refreshToken: recordedAt)
            MomentStampOverlay(
                name: authorName,
                momentTitle: localizedMomentTitle,
                day: day,
                mode: .review,
                timestamp: recordedAt,
                overlayText: editingCaption ? nil : liveOverlayText,
                clipSeconds: clipLength.seconds
            )

            if challengeID != nil, targetAuthorID == nil || targetAuthorID == "local" || targetAuthorID == myID {
                if editingCaption {
                    CaptionOverlayEditor(text: $captionDraft, isFocused: $captionFocused)
                } else {
                    // Tap the center to add/edit the caption — same spot it
                    // appears in the final film, so what you see is what ships.
                    Button {
                        captionDraft = liveOverlayText ?? ""
                        editingCaption = true
                        captionFocused = true
                    } label: {
                        if let text = liveOverlayText, !text.isEmpty {
                            // Invisible hit target over the existing text.
                            Color.clear
                                .contentShape(Rectangle())
                        } else {
                            Label(Strings.addCaption, systemImage: "text.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.35), in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Identity.tint(for: authorName), lineWidth: 3)
        }
        .onChange(of: captionFocused) { _, focused in
            if !focused, editingCaption { saveCaption() }
        }
        .onSubmit { captionFocused = false }
    }

    private func saveCaption() {
        editingCaption = false
        guard let challengeID else { return }
        store.updateOverlayText(captionDraft, day: day, challengeID: challengeID)
    }
}
