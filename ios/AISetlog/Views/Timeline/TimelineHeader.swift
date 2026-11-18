import SwiftUI

struct TimelineHeader: View {
    let challenge: Challenge
    var isSyncing = false
    var onRename: ((String) -> Void)? = nil
    var fontSize: CGFloat = 29

    @State private var renaming = false
    @State private var draftTitle = ""
    @FocusState private var fieldFocused: Bool

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    private var showsTitle: Bool {
        challenge.title != "Live With Me" && challenge.title != "和我过一天"
    }

    var body: some View {
        if let onRename {
            if renaming {
                TextField("", text: $draftTitle, prompt: Text(Strings.roomNamePlaceholder))
                    .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .tint(Color.oneDayBrand)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        let name = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { onRename(name) }
                        renaming = false
                    }
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

    private var title: some View {
        HStack(spacing: 8) {
            if showsTitle {
                Text(presenter.displayTitle)
                    .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(fontSize < 29 ? 1 : 2)
            } else if onRename != nil {
                Text(Strings.roomNamePlaceholder)
                    .font(.system(size: fontSize, weight: .heavy, design: .rounded))
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
