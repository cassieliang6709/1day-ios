import SwiftUI

/// The one look control that makes sense away from a picture: whether the grade
/// should stick, plus a way out of one you can't see.
///
/// The dials are deliberately not here. A dial you can't see the effect of is a
/// dial you're guessing at, so all three live on the screen with the picture on
/// it. This page used to offer four presets to start from; those are gone, and
/// nothing replaced them, because a starting point you pick without a picture in
/// front of you is the same guess in a different shape.
struct LookSettingsView: View {
    @AppStorage(PersonalEffectParameters.storageKey)
    private var look: PersonalEffectParameters = .none
    @AppStorage(PersonalEffectParameters.stickyKey) private var lookIsSticky = false
    /// Bound only so a language change re-renders the page.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// What the row one level up says.
    static func summary(for look: PersonalEffectParameters) -> String {
        look.isIdentity ? Strings.lookAsShot : Strings.lookCustom
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(Strings.lookSetting, value: Self.summary(for: look))
                // The escape hatch. Someone who left a dial somewhere odd and
                // switched the app off before noticing has no picture in front
                // of them to fix it against, and this page is where they'd come
                // looking.
                Button(Strings.lookReset) { look = .none }
                    .disabled(look.isIdentity)
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
