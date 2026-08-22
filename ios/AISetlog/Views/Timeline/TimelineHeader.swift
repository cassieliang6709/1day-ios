import SwiftUI

/// The top of the timeline: what this story is, who's in it, and how far the
/// day has got. Small on purpose — the line below it is the content.
struct TimelineHeader: View {
    let challenge: Challenge
    let memberNames: [String]
    let myName: String?
    @Binding var viewMode: StoryViewMode
    var isSyncing = false
    var syncError: String?

    @State private var didCopyCode = false

    private var schedule: StorySchedule { StorySchedule(challenge) }
    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            title

            if challenge.isShared, !memberNames.isEmpty {
                roster
            }

            if challenge.isShared, let code = challenge.roomCode {
                inviteCode(code)
            }

            stats

            if let syncError {
                Label(syncError, systemImage: "icloud.slash")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(presenter.displayTitle)
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(2)

                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.oneDayBlue)
                }
            }

            Text(challenge.isShared ? Strings.everyonesMoments : schedule.spanLabel)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        }
    }

    /// Faces first — a shared story should show the people before the numbers.
    /// Pending members stay visible, hollowed out, so the group never shrinks.
    private var roster: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(memberNames, id: \.self) { name in
                    AvatarBadge(name: name, isYou: name == myName)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// The join code, in full, on the screen the owner is already looking at.
    /// Sharing used to mean opening a share sheet and pulling six characters
    /// out of a sentence — fine for iMessage, useless when you just want to
    /// read the code aloud. Tapping copies the bare code, not the blurb.
    private func inviteCode(_ code: String) -> some View {
        Button {
            UIPasteboard.general.string = code
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.15)) { didCopyCode = true }
        } label: {
            HStack(spacing: 8) {
                Text(Strings.inviteCodeLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)

                Text(code)
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color.oneDayBlue)

                Image(systemName: didCopyCode ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(didCopyCode ? Color.oneDayMint : OneDay.inkFaint)

                if didCopyCode {
                    Text(Strings.inviteCodeCopied)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayMint)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OneDay.surfaceSoft.opacity(0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .task(id: didCopyCode) {
            guard didCopyCode else { return }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.2)) { didCopyCode = false }
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            OneDayChip(
                icon: "circle.grid.2x2.fill",
                text: "\(challenge.recordedCount)/\(challenge.cards.count)")

            OneDayChip(
                icon: "clock",
                text: challenge.resolvedClipLength.secondsLabel,
                tint: .oneDayLavender)

            if challenge.recordedCount > 0 {
                OneDayChip(icon: "film", text: schedule.filmDuration, tint: .oneDayMint)
            }

            Spacer(minLength: 8)

            ViewModeToggle(mode: $viewMode)
        }
    }
}

/// Renaming a story and its moment prompts. A plain form on purpose — this is
/// maintenance, not part of the emotional flow.
struct EditPlanSheet: View {
    let challenge: Challenge
    let onSave: (String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var moments: [String]
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    init(challenge: Challenge, onSave: @escaping (String, [String]) -> Void) {
        self.challenge = challenge
        self.onSave = onSave
        _title = State(initialValue: challenge.title)
        _moments = State(initialValue: challenge.cards.map { card in
            challenge.momentValue(forSlot: card.day) ?? Strings.dayN(card.day)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Strings.planTitle) {
                    TextField(Strings.planTitle, text: $title)
                }
                Section {
                    ForEach(moments.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.oneDayBlue, in: Circle())
                            TextField(
                                Strings.promptN(index + 1),
                                text: Binding(
                                    get: { MomentCatalog.localize(moments[index]) },
                                    set: { moments[index] = $0 }))
                        }
                    }
                } header: {
                    Text(Strings.captureTitles)
                } footer: {
                    Text(Strings.editPlanFootnote(shared: challenge.isShared))
                }
            }
            .navigationTitle(Strings.editPlan)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.save) {
                        onSave(
                            title.trimmingCharacters(in: .whitespacesAndNewlines),
                            moments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && moments.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
