import SwiftUI

/// The top of the timeline: what this story is and who's in it.
///
/// It no longer says how far the day has got. That was a `RoomProgress` the
/// header only used to print `0/3` beside two other numbers, and the bar
/// underneath says it better; the parameter went with the line.
struct TimelineHeader: View {
    let challenge: Challenge
    /// Who's in the room. Nil for a solo story, which has nobody to name.
    let cast: RoomCast?
    var isSyncing = false

    @Environment(\.roomPreviewMediaScope) private var previewMedia
    @State private var didCopyCode = false

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            title

            if let cast, !cast.members.isEmpty {
                RoomRoster(cast: cast)
            }

            if previewMedia == nil, challenge.isShared, let code = challenge.roomCode {
                inviteCode(code)
            }
        }
    }

    /// Just the title.
    ///
    /// Under it there used to be a subtitle with the date, a row of three chips
    /// with the clip length and the film's runtime, and a captioned progress
    /// bar with the count — three stacked lines holding one short number each,
    /// about a third of the screen spent on `9月17日`, `2秒`, `0/3` before the
    /// story itself got a pixel. 1.3 merged them into one line, and then deleted
    /// that line too: none of the three is why you opened the story, and the
    /// thin bar below already answers the only one you might want at a glance.
    ///
    /// The numbers are not lost — they live in the bar's accessibility label
    /// (`StoryProgressBar`), the clip length is on the camera as 每段 2 秒 where
    /// it is about to matter, and the runtime is on the film screen.
    private var title: some View {
        HStack(spacing: 8) {
            Text(presenter.displayTitle)
                .font(.system(size: 29, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .lineLimit(2)

            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.oneDayBrand)
            }
        }
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
                    .foregroundStyle(Color.oneDayBrand)

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
                                .background(Color.oneDayBrand, in: Circle())
                            TextField(
                                Strings.promptN(index + 1),
                                text: Binding(
                                    get: { MomentCatalog.localize(moments[index]) },
                                    set: { moments[index] = $0 }))
                        }
                    }
                } header: {
                    Text(Strings.captureTitles)
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
