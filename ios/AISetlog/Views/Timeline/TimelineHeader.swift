import SwiftUI

/// The top of the timeline: what this story is called.
///
/// It no longer says how far the day has got. That was a `RoomProgress` the
/// header only used to print `0/3` beside two other numbers, and the bar
/// underneath says it better; the parameter went with the line.
///
/// A room used to add 「2 人 · 邀请码 KPADC7」 under the title. Gone (1.5):
/// the columns below already show who's here, and the code goes out through
/// 邀请 in the nav bar, which is the only place anyone sends it from.
struct TimelineHeader: View {
    let challenge: Challenge
    var isSyncing = false

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    /// 「和我过一天」 is the name 按时间拍 used to give every story it made —
    /// a template's label, not a name anybody chose — so a story still
    /// carrying it shows no title rather than that. Stories made since are
    /// named for their date, and a name you typed always shows.
    private var showsTitle: Bool {
        let byTime = ChallengeTemplate.liveWithMe.name
        return challenge.title != byTime.en && challenge.title != byTime.zh
    }

    var body: some View {
        if showsTitle || isSyncing {
            title
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
            if showsTitle {
                Text(presenter.displayTitle)
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(2)
            }

            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.oneDayBrand)
            }
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
                                .foregroundStyle(OneDay.onBrand)
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
