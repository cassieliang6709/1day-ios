import SwiftUI

/// Where clips wait when there was nowhere to file them.
///
/// PR-4 gave "keep it for now" somewhere to write to; without this screen that
/// was a one-way door — the clip survived, but nobody could ever reach it
/// again. Filing and deleting both live here, and both take the file with them
/// so a draft can't outlive its bytes or the other way round.
struct ClipDraftsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(ClipDraftStore.self) private var drafts

    @State private var filing: ClipDraft?
    @State private var toast: String?

    /// Bound only so a language change re-renders the list.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 3)

                if drafts.isEmpty {
                    emptyState
                } else {
                    list
                }

                if let toast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.black.opacity(0.65), in: Capsule())
                            .padding(.bottom, 40)
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle(Strings.draftsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
            .confirmationDialog(
                Strings.archiveDraft,
                isPresented: Binding(
                    get: { filing != nil },
                    set: { if !$0 { filing = nil } }),
                titleVisibility: .visible
            ) {
                if let draft = filing {
                    ForEach(candidates(for: draft)) { challenge in
                        Button(ChallengePresenter(challenge: challenge).displayTitle) {
                            archive(draft, to: challenge)
                        }
                    }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(Strings.draftsTotalSize) \(Strings.draftSize(drafts.totalByteSize))")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .padding(.horizontal, 4)

                ForEach(drafts.sortedDrafts) { draft in
                    row(draft)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ draft: ClipDraft) -> some View {
        let canFile = !candidates(for: draft).isEmpty
        return HStack(spacing: 13) {
            ClipThumbnail(url: drafts.url(for: draft), refreshToken: draft.recordedAt)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text(recordedLine(draft))
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)

                Text(detailLine(draft))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)

                if !canFile {
                    Text(Strings.noPlaceForDraft(landscape: draft.orientation == .landscape))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            Menu {
                // Only offered when it would work: a disabled row that opens a
                // sheet with no options in it is just a slower dead end.
                if canFile {
                    Button(Strings.archiveDraft, systemImage: "tray.and.arrow.down") {
                        filing = draft
                    }
                }
                Button(Strings.deleteDraft, systemImage: "trash", role: .destructive) {
                    drafts.remove(draft)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(OneDay.inkSoft)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .padding(12)
        .glassSurface(radius: OneDay.Radius.card)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            OneDayBuddy(size: 68)
            Text(Strings.draftsEmpty)
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }

    // MARK: - Copy

    private func recordedLine(_ draft: ClipDraft) -> String {
        draft.recordedAt.formatted(
            .dateTime.month().day().hour().minute()
                .locale(AppLanguage.effective.locale))
    }

    private func detailLine(_ draft: ClipDraft) -> String {
        let frame = draft.orientation == .landscape
            ? Strings.orientationLandscape
            : Strings.orientationPortrait
        return "\(frame) · \(Strings.draftSize(draft.byteSize))"
    }

    // MARK: - Actions

    private func candidates(for draft: ClipDraft) -> [Challenge] {
        ClipFiling.candidates(in: store.challenges, orientation: draft.orientation)
    }

    /// File the draft, then drop it — but only once the clip has actually
    /// landed. `saveClip` reports failure by doing nothing, so deleting first
    /// would throw away the only remaining copy.
    private func archive(_ draft: ClipDraft, to challenge: Challenge) {
        // No open slot means no filing. The old code filed into the day the
        // story was on, which for a full story is a day that already holds a
        // clip: the draft overwrote it, and the check below — true before the
        // save as well as after — then deleted the draft either way.
        guard let day = ClipFiling.targetDay(in: challenge) else {
            showToast(Strings.storyIsFull)
            return
        }
        store.saveClip(
            from: drafts.url(for: draft),
            day: day,
            challengeID: challenge.id,
            overlayText: draft.overlayText)

        guard store.challenge(challenge.id)?.cards
            .first(where: { $0.day == day })?.clipFileName != nil
        else {
            showToast(Strings.draftArchiveFailed)
            return
        }
        drafts.remove(draft)
        showToast(Strings.filedTo(ChallengePresenter(challenge: challenge).displayTitle))
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.9))
            if toast == text { withAnimation { toast = nil } }
        }
    }
}

/// The camera tab's way in: only there when there's something waiting, so it
/// never becomes another permanent piece of chrome over the viewfinder.
struct DraftsEntryButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(Strings.draftsPending(count))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("drafts-entry")
    }
}
