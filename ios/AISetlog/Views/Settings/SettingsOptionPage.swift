import SwiftUI

/// A settings choice that can be listed on a screen of its own: every case, a
/// name for each, and one line explaining what the choice does.
protocol SettingsOption: CaseIterable, Identifiable, Hashable {
    var displayName: String { get }
}

extension AppLanguage: SettingsOption {}
extension AppAppearance: SettingsOption {}

/// One choice, one screen. Settings used to lay every option of every picker
/// out on the front page, which cost most of a medium-detent sheet to show
/// three things nobody changes twice. The row above now says which one is
/// picked; the list and the sentence explaining it live here, where you read
/// the sentence at the moment you're choosing.
struct SettingsOptionPage<Option: SettingsOption>: View
where Option.AllCases: RandomAccessCollection {
    let title: String
    let footnote: String
    @Binding var selection: Option

    var body: some View {
        Form {
            Section {
                // Still a Picker rather than hand-rolled rows: it keeps the
                // checkmark, the VoiceOver phrasing and the keyboard handling
                // that a list of Buttons quietly loses.
                Picker(title, selection: $selection) {
                    ForEach(Option.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(footnote)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
