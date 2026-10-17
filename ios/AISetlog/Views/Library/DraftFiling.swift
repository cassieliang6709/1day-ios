import SwiftUI

/// Filing and deleting a draft, shared by `ClipDraftsView` and 我的's grid so
/// both take the same path: the clip lands in a story before the draft and its
/// file are dropped.
@MainActor
enum DraftFiler {
    static func candidates(for draft: ClipDraft, in store: ChallengeStore) -> [Challenge] {
        ClipFiling.candidates(in: store.challenges, orientation: draft.orientation)
    }

    /// Why 归档 can't run. Only asked when there are no candidates, so
    /// `blocker` never answers nil here — but a made-up explanation would be
    /// worse than none, so the nil case falls back to the symptom.
    static func blocked(for draft: ClipDraft, in store: ChallengeStore) -> DraftFilingBlocked {
        let message = switch ClipFiling.blocker(
            in: store.challenges, orientation: draft.orientation
        ) {
        case .noStoryWithThisFrame: Strings.draftNoStoryYet
        case .everyMatchingStoryIsFull: Strings.draftEveryStoryFull
        case nil: Strings.draftNoPlace
        }
        return DraftFilingBlocked(title: Strings.draftNoPlace, message: message)
    }

    /// File the draft into every chosen story, then drop it — but only once at
    /// least one copy has actually landed. `saveClip` reports failure by doing
    /// nothing, so deleting first would throw away the only remaining copy.
    ///
    /// Each story gets its own copy in its own first open slot;
    /// `ClipFileStore.storeClip` copies the file, so the same draft URL can be
    /// handed to `saveClip` once per story. Partial success is a success for
    /// the draft: once the clip is somewhere, keeping it here too leaves a copy
    /// nobody will come back for.
    ///
    /// - Returns: the toast to show.
    static func archive(
        _ draft: ClipDraft, to challenges: [Challenge],
        store: ChallengeStore, drafts: ClipDraftStore
    ) -> String {
        var landed: [Challenge] = []
        for challenge in challenges {
            // No open slot means no filing: filing into the story's current
            // day overwrote a clip that was already there.
            guard let day = ClipFiling.targetDay(in: challenge) else { continue }
            store.saveClip(
                from: drafts.url(for: draft), day: day,
                challengeID: challenge.id, overlayText: draft.overlayText)
            if store.challenge(challenge.id)?.cards
                .first(where: { $0.day == day })?.clipFileName != nil {
                landed.append(challenge)
            }
        }

        guard !landed.isEmpty else {
            return challenges.allSatisfy { ClipFiling.targetDay(in: $0) == nil }
                ? Strings.storyIsFull
                : Strings.draftArchiveFailed
        }
        drafts.remove(draft)
        return landed.count == 1
            ? Strings.filedTo(ChallengePresenter(challenge: landed[0]).displayTitle)
            : Strings.filedToCount(landed.count)
    }
}

/// The explanation 归档 gives when it can't run. Carries its own text so the
/// alert doesn't re-derive it from a draft that may already be gone.
struct DraftFilingBlocked: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension View {
    /// Tapping a draft in 我的: 放进故事 or 删除, the delete confirmed first.
    /// `send` and `delete` skip the question and go straight to that step —
    /// the day player's own buttons.
    func draftActions(
        for draft: Binding<ClipDraft?>,
        send: Binding<ClipDraft?> = .constant(nil),
        delete: Binding<ClipDraft?> = .constant(nil)
    ) -> some View {
        modifier(DraftActionsModifier(active: draft, send: send, delete: delete))
    }
}

private struct DraftActionsModifier: ViewModifier {
    @Binding var active: ClipDraft?
    @Binding var send: ClipDraft?
    @Binding var delete: ClipDraft?

    @Environment(ChallengeStore.self) private var store
    @Environment(ClipDraftStore.self) private var drafts
    @State private var filing: ClipDraft?
    @State private var pendingDelete: ClipDraft?
    @State private var blocked: DraftFilingBlocked?
    @State private var toast: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                Strings.libraryDraftQuestion,
                isPresented: isPresent($active),
                titleVisibility: .visible,
                presenting: active
            ) { draft in
                Button(Strings.libraryFileIntoStory) { file(draft) }
                Button(Strings.deleteDraft, role: .destructive) { pendingDelete = draft }
                Button(Strings.cancel, role: .cancel) {}
            }
            .background { deleteConfirmation }
            .sheet(item: $filing) { draft in
                ClipFilingSheet(candidates: DraftFiler.candidates(for: draft, in: store)) {
                    show(DraftFiler.archive(draft, to: $0, store: store, drafts: drafts))
                }
            }
            .alert(
                blocked?.title ?? "", isPresented: isPresent($blocked), presenting: blocked
            ) { _ in
                Button(Strings.ok, role: .cancel) {}
            } message: { Text($0.message) }
            .overlay(alignment: .top) { toastView }
            .onChange(of: send) { _, draft in
                guard let draft else { return }
                send = nil
                file(draft)
            }
            .onChange(of: delete) { _, draft in
                guard let draft else { return }
                delete = nil
                pendingDelete = draft
            }
    }

    /// On a background view: two confirmation dialogs on one view fight.
    private var deleteConfirmation: some View {
        Color.clear.confirmationDialog(
            Strings.deleteDraftQuestion,
            isPresented: isPresent($pendingDelete),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { draft in
            Button(Strings.deleteDraft, role: .destructive) { drafts.remove(draft) }
            Button(Strings.cancel, role: .cancel) {}
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.7), in: Capsule())
                .transition(.opacity)
        }
    }

    private func file(_ draft: ClipDraft) {
        if DraftFiler.candidates(for: draft, in: store).isEmpty {
            blocked = DraftFiler.blocked(for: draft, in: store)
        } else {
            filing = draft
        }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.9))
            if toast == text { withAnimation { toast = nil } }
        }
    }

    private func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}
