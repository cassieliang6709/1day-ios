import SwiftUI

struct ClipDraftsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(ClipDraftStore.self) private var drafts
    @Environment(AccountStore.self) private var account

    @State private var filing: ClipDraft?
    @State private var afterSignIn: (() -> Void)?
    @State private var pendingDelete: ClipDraft?
    @State private var blocked: DraftFilingBlocked?
    @State private var toast: String?

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
            .signInGate($afterSignIn)
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
            ClipTile(url: drafts.url(for: draft), refreshToken: draft.recordedAt)
                .frame(width: 58, height: 58)

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
                Button(Strings.archiveDraft, systemImage: "tray.and.arrow.down") {
                    if canFile, account.isSignedIn {
                        filing = draft
                    } else if canFile {
                        afterSignIn = { filing = draft }
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


    private func recordedLine(_ draft: ClipDraft) -> String {
        draft.recordedAt.formatted(
            .dateTime.month().day().hour().minute()
                .locale(AppLanguage.effective.locale))
    }

    private func detailLine(_ draft: ClipDraft) -> String {
        let key = ClipCameraIndex.key(url: drafts.url(for: draft), recordedAt: draft.recordedAt)
        let camera = ClipCameraIndex.shared.cameras[key].flatMap { $0 == .standard ? nil : $0 }
        return [camera?.displayName, Strings.draftSize(draft.byteSize)]
            .compactMap { $0 }.joined(separator: " · ")
    }


    private func candidates(for draft: ClipDraft) -> [Challenge] {
        DraftFiler.candidates(for: draft, in: store)
    }

    private func filingBlocked(for draft: ClipDraft) -> DraftFilingBlocked {
        DraftFiler.blocked(for: draft, in: store)
    }

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

struct ClipFilingSheet: View {
    let candidates: [Challenge]
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
