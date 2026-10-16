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
    /// The draft whose delete is waiting on a yes. A draft is the only copy of
    /// that take — it exists because there was nowhere else to put it — so a
    /// menu item one mis-tap from 归档到… can't be the whole decision.
    @State private var pendingDelete: ClipDraft?
    @State private var blocked: DraftFilingBlocked?
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
                Strings.deleteDraftQuestion,
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { draft in
                Button(Strings.deleteDraft, role: .destructive) {
                    drafts.remove(draft)
                    pendingDelete = nil
                }
                Button(Strings.cancel, role: .cancel) { pendingDelete = nil }
            }
            .sheet(item: $filing) { draft in
                ClipFilingSheet(candidates: candidates(for: draft)) { chosen in
                    archive(draft, to: chosen)
                }
            }
            .alert(
                blocked?.title ?? "",
                isPresented: Binding(
                    get: { blocked != nil },
                    set: { if !$0 { blocked = nil } }),
                presenting: blocked
            ) { _ in
                Button(Strings.ok, role: .cancel) {}
            } message: { reason in
                Text(reason.message)
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
        .task(id: drafts.sortedDrafts.map(\.id)) {
            ClipCameraIndex.shared.load(drafts.sortedDrafts.map {
                (key: ClipCameraIndex.key(url: drafts.url(for: $0), recordedAt: $0.recordedAt),
                 url: drafts.url(for: $0))
            })
        }
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

                // Tappable, not just stated. The line names the symptom; what
                // a person wants next is what to do about it, and the row is
                // where they are looking when they want it.
                if !canFile {
                    Button {
                        blocked = filingBlocked(for: draft)
                    } label: {
                        HStack(spacing: 3) {
                            Text(Strings.draftNoPlace)
                                .lineLimit(2)
                            Image(systemName: "info.circle")
                        }
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 4)

            Menu {
                // Always offered, even when it can't run. Hiding it left the
                // menu on an unfilable draft holding nothing but 删除 — the
                // one action that ends with the clip gone — and no statement
                // anywhere of what would make filing possible. It says that
                // now, in the alert.
                Button(Strings.archiveDraft, systemImage: "tray.and.arrow.down") {
                    if canFile {
                        filing = draft
                    } else {
                        blocked = filingBlocked(for: draft)
                    }
                }
                Button(Strings.deleteDraft, systemImage: "trash", role: .destructive) {
                    pendingDelete = draft
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(OneDay.inkSoft)
                    .frame(width: 44, height: 44)
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

    /// 「胶片机 · 3.2 MB」: the camera it was filmed with, read from the file
    /// (`ClipCameraIndex`), then its size. No camera, or not read yet: size only.
    private func detailLine(_ draft: ClipDraft) -> String {
        let key = ClipCameraIndex.key(url: drafts.url(for: draft), recordedAt: draft.recordedAt)
        let camera = ClipCameraIndex.shared.cameras[key].flatMap { $0 == .standard ? nil : $0 }
        return [camera?.displayName, Strings.draftSize(draft.byteSize)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Actions

    private func candidates(for draft: ClipDraft) -> [Challenge] {
        DraftFiler.candidates(for: draft, in: store)
    }

    private func filingBlocked(for draft: ClipDraft) -> DraftFilingBlocked {
        DraftFiler.blocked(for: draft, in: store)
    }

    /// See `DraftFiler.archive`: shared with 我的's grid.
    private func archive(_ draft: ClipDraft, to challenges: [Challenge]) {
        showToast(DraftFiler.archive(draft, to: challenges, store: store, drafts: drafts))
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
///
/// `compact` is the camera's top-bar form: tray and count only, sized to the
/// slot beside the wordmark. The full sentence used to float 88pt down, inside
/// the frame, where on a small phone it sat on the timer chip; VoiceOver still
/// gets the sentence.
struct DraftsEntryButton: View {
    let count: Int
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 4 : 7) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(compact ? "\(count)" : Strings.draftsPending(count))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.55), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.draftsPending(count))
        .accessibilityIdentifier("drafts-entry")
    }
}
