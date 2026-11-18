import SwiftUI

protocol SettingsOption: CaseIterable, Identifiable, Hashable {
    var displayName: String { get }
}

extension AppLanguage: SettingsOption {}
extension AppAppearance: SettingsOption {}
extension AppSkin: SettingsOption {}

struct SettingsOptionPage<Option: SettingsOption>: View
where Option.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Option

    var body: some View {
        Form {
            Section {
                Picker(title, selection: $selection) {
                    ForEach(Option.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
