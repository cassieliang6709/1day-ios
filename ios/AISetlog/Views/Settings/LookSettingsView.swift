import SwiftUI

/// The two look controls that make sense away from a picture: which preset to
/// start from, and whether it should stick.
///
/// The dials are deliberately still not here. A dial you can't see the effect
/// of is a dial you're guessing at, so fine-tuning stays on the screen with the
/// picture on it — this page only sets where that screen starts.
struct LookSettingsView: View {
    @AppStorage(GentleLook.storageKey) private var look: GentleLook = .none
    @AppStorage(GentleLook.stickyKey) private var lookIsSticky = false
    /// Bound only so a language change re-renders the page.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// What the row one level up says. Nil preset means a dial has been moved,
    /// and calling that "原样" would be a lie.
    static func summary(for look: GentleLook) -> String {
        guard let key = look.presetKey else { return Strings.lookCustom }
        return GentleLook.presetName(key)
    }

    var body: some View {
        Form {
            Section {
                Picker(Strings.lookSetting, selection: $look) {
                    ForEach(GentleLook.presets, id: \.key) { preset in
                        Text(GentleLook.presetName(preset.key)).tag(preset.look)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(Strings.lookFootnote)
            }

            Section {
                Toggle(Strings.lookRemember, isOn: $lookIsSticky)
            } footer: {
                Text(Strings.lookRememberFootnote)
            }
        }
        .navigationTitle(Strings.lookSetting)
        .navigationBarTitleDisplayMode(.inline)
    }
}
