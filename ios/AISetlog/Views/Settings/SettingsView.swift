import SwiftUI

/// App settings. Language is the one knob for now — it drives every template
/// name, moment prompt, and localized string across the app.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(Strings.language, selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(Strings.language)
                } footer: {
                    Text(Strings.languageFootnote)
                }
            }
            .navigationTitle(Strings.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
