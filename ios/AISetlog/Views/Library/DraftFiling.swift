import SwiftUI

@MainActor
enum DraftFiler {
    static func candidates(for draft: ClipDraft, in store: ChallengeStore) -> [Challenge] {
        ClipFiling.rooms(in: store.challenges)
    }

    static func blocked(for draft: ClipDraft, in store: ChallengeStore) -> DraftFilingBlocked {
        DraftFilingBlocked(title: Strings.draftNoPlace, message: "")
    }

    static func archive(
        _ draft: ClipDraft, to challenges: [Challenge],
        store: ChallengeStore, drafts: ClipDraftStore
    ) -> String {
        var landed: [Challenge] = []
        for challenge in challenges {
            if challenge.isShared {
                if store.sendToRoom(
                    from: drafts.url(for: draft), roomID: challenge.id,
                    captions: draft.captions, recordedAt: draft.recordedAt) {
                    landed.append(challenge)
                }
                continue
            }
            guard let day = ClipFiling.targetDay(in: challenge) else { continue }
            store.saveClip(
                from: drafts.url(for: draft), day: day,
                challengeID: challenge.id, captions: draft.captions,
                recordedAt: draft.recordedAt)
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

struct DraftFilingBlocked: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension View {
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
    @Environment(AccountStore.self) private var account
    @State private var filing: ClipDraft?
    @State private var afterSignIn: (() -> Void)?
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
            .signInGate($afterSignIn)
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
        } else if account.isSignedIn {
            filing = draft
        } else {
            afterSignIn = { filing = draft }
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
