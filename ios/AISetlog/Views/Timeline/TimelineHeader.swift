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
    /// A room's name can be changed by anyone in it (1.5): tapping the title
    /// turns it into the text field, in place — no dialog. Return saves;
    /// tapping away leaves it as it was. Nil keeps the title plain text.
    var onRename: ((String) -> Void)? = nil

    @State private var renaming = false
    @State private var draftTitle = ""
    @FocusState private var fieldFocused: Bool

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    /// 「和我过一天」 is the name 按时间拍 used to give every story it made —
    /// a template's label, not a name anybody chose — so a story still
    /// carrying it shows no title rather than that. Stories made since are
    /// named for their date, and a name you typed always shows.
    private var showsTitle: Bool {
        challenge.title != "Live With Me" && challenge.title != "和我过一天"
    }

    var body: some View {
        if let onRename {
            if renaming {
                TextField("", text: $draftTitle, prompt: Text(Strings.roomNamePlaceholder))
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .tint(Color.oneDayBrand)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        let name = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { onRename(name) }
                        renaming = false
                    }
                    // Tapped away without Return: nothing changes.
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused { renaming = false }
                    }
                    .onAppear { fieldFocused = true }
                    .accessibilityIdentifier("room-title-field")
            } else {
                Button {
                    draftTitle = showsTitle ? challenge.title : ""
                    renaming = true
                } label: {
                    title
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("room-title")
            }
        } else if showsTitle || isSyncing {
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
            } else if onRename != nil {
                // A room still called 和我过一天 has no title to tap; this is it.
                Text(Strings.roomNamePlaceholder)
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .lineLimit(1)
            }

            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.oneDayBrand)
            }
        }
    }
}
