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
            .sheet(item: $filing) { draft in
                ClipFilingSheet(candidates: candidates(for: draft)) { chosen in
                    archive(draft, to: chosen)
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
                    Text(Strings.noPlaceForDraft(draft.orientation))
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
        let frame = switch draft.orientation {
        case .portrait: Strings.orientationPortrait
        case .landscape: Strings.orientationLandscape
        case .square: Strings.orientationSquare
        }
        return "\(frame) · \(Strings.draftSize(draft.byteSize))"
    }

    // MARK: - Actions

    private func candidates(for draft: ClipDraft) -> [Challenge] {
        ClipFiling.candidates(in: store.challenges, orientation: draft.orientation)
    }

    /// File the draft into every chosen story, then drop it — but only once at
    /// least one copy has actually landed. `saveClip` reports failure by doing
    /// nothing, so deleting first would throw away the only remaining copy.
    ///
    /// Takes a list as of 1.3. Each story gets its own copy in its own first
    /// open slot; `ClipFileStore.storeClip` copies the file, so the same draft
    /// URL can be handed to `saveClip` once per story.
    ///
    /// Partial success is a success for the draft's purposes: it exists because
    /// the clip had nowhere to go, and once it is somewhere, keeping it here as
    /// well leaves a copy nobody will come back for. What failed is named.
    private func archive(_ draft: ClipDraft, to challenges: [Challenge]) {
        var landed: [Challenge] = []
        var refused: [Challenge] = []

        for challenge in challenges {
            // No open slot means no filing. The old code filed into the day the
            // story was on, which for a full story is a day that already holds
            // a clip: the draft overwrote it, and the check below — true before
            // the save as well as after — then deleted the draft either way.
            guard let day = ClipFiling.targetDay(in: challenge) else {
                refused.append(challenge)
                continue
            }
            store.saveClip(
                from: drafts.url(for: draft),
                day: day,
                challengeID: challenge.id,
                overlayText: draft.overlayText)

            if store.challenge(challenge.id)?.cards
                .first(where: { $0.day == day })?.clipFileName != nil {
                landed.append(challenge)
            } else {
                refused.append(challenge)
            }
        }

        guard !landed.isEmpty else {
            showToast(
                refused.count == challenges.count && challenges.allSatisfy {
                    ClipFiling.targetDay(in: $0) == nil
                }
                    ? Strings.storyIsFull
                    : Strings.draftArchiveFailed)
            return
        }

        drafts.remove(draft)
        showToast(
            landed.count == 1
                ? Strings.filedTo(ChallengePresenter(challenge: landed[0]).displayTitle)
                : Strings.filedToCount(landed.count))
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.9))
            if toast == text { withAnimation { toast = nil } }
        }
    }
}

/// Picking the stories a clip goes into — one, or several.
///
/// Replaces the `confirmationDialog` both filing paths used to raise, which
/// listed story names and filed into whichever one you tapped. One clip could
/// only ever have one home, so a take that belonged both in your own story and
/// in the room you share with the people who were there meant filming it twice.
/// `ClipFileStore.storeClip` copies rather than moves, so nothing about the
/// storage layer required that limit.
///
/// Every row says which slot the clip would land in, because with several
/// selected "where does each copy go" stops being obvious — see
/// `ClipFiling.targetDay`, whose answer is the first empty moment, per story.
struct ClipFilingSheet: View {
    let candidates: [Challenge]
    /// Called with the chosen stories, in the order they were listed. Never
    /// called empty — the button is disabled until something is picked.
    let onFile: ([Challenge]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<UUID> = []

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 4)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(candidates) { row($0) }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(Strings.fileThisClipTo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.fileToCount(picked.count)) {
                        onFile(candidates.filter { picked.contains($0.id) })
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(picked.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if picked.isEmpty {
                    Text(Strings.pickAtLeastOneStory)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private func row(_ challenge: Challenge) -> some View {
        let isOn = picked.contains(challenge.id)
        let slot = ClipFiling.targetDay(in: challenge)
            .flatMap { challenge.momentValue(forSlot: $0) }
            .map { MomentCatalog.localize($0) }
        return Button {
            if isOn { picked.remove(challenge.id) } else { picked.insert(challenge.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isOn ? Color.oneDayBrand : OneDay.inkFaint)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 3) {
                    Text(ChallengePresenter(challenge: challenge).displayTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .lineLimit(1)

                    if let slot {
                        Text(Strings.landsIn(slot))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if challenge.isShared {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.oneDayLavender)
                }
            }
            .padding(13)
            .glassSurface(radius: OneDay.Radius.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
