import SwiftUI

/// App-level preferences: display and language, the account, and the small
/// print. Anything with more than a couple of options is a row here and a page
/// behind it — see `body`.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account

    @State private var showDeleteConfirmation = false
    /// Raised when the deletion stopped part-way. Nothing on the device has
    /// been touched at that point, so there is genuinely something to retry.
    @State private var deleteFailed = false
    @State private var isDeleting = false
    @State private var showSignIn = false
    /// Held locally so a half-typed name never reaches the rooms.
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    /// Written by the picker below, read by every `AvatarDot` — held here too
    /// so this screen repaints its own header the moment a dot is tapped.
    @AppStorage(Identity.myTintKey) private var myTintIndex = -1

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system

    /// Who you are, what you've made, then the two things worth changing.
    ///
    /// This screen has been through three rewrites of its *structure* — nine
    /// sections, then four, now two — and for the first two it stayed a stock
    /// `Form`, which made it the one page in the app rendered in system greys
    /// and system blue. Coming here from the home screen felt like leaving the
    /// app.
    ///
    /// So: the app's own canvas and glass cards, and a header that answers
    /// "who am I here" before it offers anything to change. The three counts
    /// are the only new content, and they're the only reason to open this page
    /// when you don't want to change a setting.
    ///
    /// 通知 is gone as of 1.3, both rows of it. 晚间拍摄提醒 asked the person
    /// to schedule a nudge about a story they were already looking at, and
    /// 好友动态 was a push subscription for rooms most people never make. The
    /// scheduler and the subscription service are still here and still guard on
    /// their flags — with nothing left to set those flags, both stay off, which
    /// is the behaviour we want and the reason the services didn't need
    /// touching. See `ReminderService` and `SharedActivityNotificationService`.
    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        identityHeader
                        statsRow
                        group(Strings.displayAndLanguage, rows: displayRows)
                        // Signed out there is nothing here but "sign in",
                        // which the header above already offers — one screen
                        // asking the same thing twice.
                        if account.isSignedIn {
                            group(Strings.account, rows: accountRows)
                        }
                        smallPrint
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(Strings.meTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
            // Outside the scroll content, as it was outside the Form: a sheet
            // presented from inside a row of an already-presented sheet takes
            // the whole settings panel down with it.
            .sheet(isPresented: $showSignIn) {
                SignInView { showSignIn = false }
            }
            .onAppear { draftName = account.account?.displayName ?? "" }
            .onChange(of: account.account?.displayName) { _, name in
                guard !nameFocused else { return }
                draftName = name ?? ""
            }
            .confirmationDialog(
                Strings.deleteAccountTitle,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(Strings.deleteAccountConfirm, role: .destructive) {
                    isDeleting = true
                    Task {
                        // Through the journalled service, so a network failure
                        // stops and says so instead of wiping the device and
                        // reporting success it can't vouch for.
                        let service = AccountDeletionService(store: store)
                        let gone = await service.run()
                        isDeleting = false
                        if gone {
                            dismiss()
                        } else {
                            // Nothing local has been touched, so there is
                            // something to come back to. Saying "try again" is
                            // only honest because of that ordering.
                            deleteFailed = true
                        }
                    }
                }
                Button(Strings.cancel, role: .cancel) {}
            } message: {
                Text(Strings.deleteAccountWarning)
            }
            .alert(Strings.deleteAccountFailedTitle, isPresented: $deleteFailed) {
                Button(Strings.deleteAccountConfirm, role: .destructive) {
                    showDeleteConfirmation = true
                }
                Button(Strings.cancel, role: .cancel) {}
            } message: {
                Text(Strings.deleteAccountFailedMessage)
            }
            .overlay {
                if isDeleting {
                    ProgressView(Strings.deletingAccount)
                        .controlSize(.large)
                }
            }
        }
        // One detent, not two. The medium one couldn't reach past "Appearance"
        // even as a bare list, and it certainly can't with a header on top.
        .presentationDetents([.large])
    }

    // MARK: - Who you are

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 11) {
            identityRow
            // Shown signed out too. The colour is stored against your name, so
            // it used to need one — and gating it meant somebody who films
            // alone and never signs in could never change their own avatar.
            tintPicker
        }
        .padding(.vertical, 4)
    }

    /// Seven dots. Tap one and it's yours — including the one somebody else in
    /// the room already has.
    ///
    /// The colour used to be a hash of your name, with no way to change it,
    /// which is fine until the name you actually go by hands you the green.
    /// Uniqueness inside a room was the reason for the hash, and it is not
    /// worth overriding the person's own choice: every avatar in the app has
    /// the name next to it or under it.
    private var tintPicker: some View {
        VStack(spacing: 8) {
            ForEach(Array(tintRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) { tintDots(row) }
            }
        }
        .accessibilityIdentifier("avatar-tints")
    }

    /// Six per row. Twelve in one row is a 24pt dot with 3pt between them —
    /// the row that used to hold seven was already at its limit.
    private var tintRows: [[Int]] {
        let all = Array(Identity.paletteUIColors.indices)
        return stride(from: 0, to: all.count, by: 6).map {
            Array(all[$0..<min($0 + 6, all.count)])
        }
    }

    @ViewBuilder
    private func tintDots(_ indices: [Int]) -> some View {
        ForEach(indices, id: \.self) { index in
            let ui = Identity.paletteUIColors[index]
                let chosen = index == Identity.tintIndex(for: tintOwnerName)
                Button {
                    Identity.chooseTint(index, forName: tintOwnerName)
                    myTintIndex = index
                } label: {
                    Circle()
                        .fill(Color(uiColor: ui).gradient)
                        .frame(height: 26)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            if chosen {
                                Circle()
                                    .strokeBorder(OneDay.ink, lineWidth: 2.5)
                                    .frame(width: 33, height: 33)
                            }
                        }
                        .contentShape(Rectangle())
                }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.avatarColourN(index + 1))
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
    }

    /// Whose colour this is. `"local"` for a device with no account on it —
    /// the same stand-in `ChallengeStore.currentAuthor` uses, so a solo user is
    /// a consistent person throughout the app rather than a special case here.
    private var tintOwnerName: String {
        let name = account.account?.displayName ?? ""
        return name.isEmpty ? "local" : name
    }

    private var identityRow: some View {
        HStack(spacing: 13) {
            AvatarDot(name: account.account?.displayName, size: 54)

            if account.isSignedIn {
                VStack(alignment: .leading, spacing: 2) {
                    // The name is editable in place, which is what makes the
                    // caption under it true. It was a right-aligned text field
                    // in a row called "Your name", three groups further down.
                    TextField(Strings.yourNamePlaceholder, text: $draftName)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .tint(Color.oneDayBrand)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(commitName)
                        .accessibilityIdentifier("your-name")
                }
                .onChange(of: nameFocused) { _, focused in
                    if !focused { commitName() }
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(Strings.notSignedIn)
                        .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    // Signing out used to be one-way from this screen: the
                    // only other sign-in gate is in front of a shared story,
                    // so getting back in meant starting one.
                    Button(Strings.signIn) { showSignIn = true }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayBrand)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Three numbers the app can actually count.
    private var statsRow: some View {
        HStack(spacing: 9) {
            stat(store.challenges.count, Strings.statStories)
            stat(
                store.challenges.reduce(0) { $0 + $1.recordedCount },
                Strings.statMoments)
            // `!cards.isEmpty` first: a story with no moments in it satisfies
            // "every moment filmed" vacuously, and counting it as finished
            // would be the app congratulating somebody for nothing.
            stat(
                store.challenges.filter {
                    !$0.cards.isEmpty && $0.recordedCount >= $0.cards.count
                }.count,
                Strings.statFinished)
        }
    }

    private func stat(_ value: Int, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OneDay.ink)
            Text(unit)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .glassSurface(radius: 16)
    }

    // MARK: - Groups

    private func group<Rows: View>(_ title: String, rows: Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            VStack(spacing: 0) { rows }
                .glassSurface(radius: 18)
        }
    }

    private var smallPrint: some View {
        HStack(spacing: 6) {
            Link(Strings.privacyPolicy, destination: Self.privacyPolicyURL)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.oneDayBrand)
            Text("·")
            Text(Self.versionString)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(OneDay.inkFaint)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: - Display & language

    /// Three decisions you make once and forget. One line each, showing what
    /// it's currently set to; the options and the sentence explaining them are
    /// on the screen behind the row.
    ///
    /// The look dials are deliberately not here, on this page or the one behind
    /// it — a dial you can't see the effect of is a dial you're guessing at, so
    /// fine-tuning stays on the screen with the picture on it.
    @ViewBuilder
    private var displayRows: some View {
        // 回看的样子 used to be the first row here. It is gone on purpose: the
        // three dials only mean anything with a picture behind them, and that
        // is the review screen's own ✦ button. A settings page that can change
        // how your films look, with no film on it, is a page you set blind.
        SettingsLinkRow(
            symbol: "circle.lefthalf.filled",
            accent: .oneDayNavy,
            title: Strings.appearance,
            value: appAppearance.displayName
        ) {
            SettingsOptionPage(
                title: Strings.appearance,
                selection: $appAppearance)
        }
        rowDivider
        SettingsLinkRow(
            symbol: "globe",
            accent: .oneDayBrand,
            title: Strings.language,
            value: appLanguage.displayName
        ) {
            SettingsOptionPage(
                title: Strings.language,
                selection: $appLanguage)
        }
    }

    // MARK: - Account

    /// Sign out and delete. Both were missing entirely: `signOut()` existed on
    /// `AccountStore` but nothing in the UI ever called it, and there was no
    /// way at all to delete an account — which App Store guideline 5.1.1(v)
    /// requires of any app that creates one.
    ///
    /// The name moved to the header, which is where somebody looking for it
    /// would look. Only the two irreversible actions are left here.
    @ViewBuilder
    private var accountRows: some View {
        if account.isSignedIn {
            SettingsButtonRow(
                symbol: "checkmark.seal.fill",
                accent: .oneDayMint,
                title: Strings.signedInWithApple,
                caption: nil,
                action: nil)
            rowDivider
            // Through the store, not straight at the account: the rooms hold a
            // cache keyed by who I am.
            SettingsButtonRow(
                symbol: "rectangle.portrait.and.arrow.right",
                accent: .oneDayNavy,
                title: Strings.signOut,
                caption: nil
            ) { store.signOut() }
            rowDivider
            // Only an account that exists can be deleted. Offering this while
            // signed out put a button that erases every story on the device
            // under a heading nobody reads as "erase my stories" — and there
            // was nothing there to delete anyway.
            SettingsButtonRow(
                symbol: "trash.fill",
                accent: .red,
                title: Strings.deleteAccount,
                caption: nil,
                isDestructive: true,
                isDisabled: isDeleting
            ) { showDeleteConfirmation = true }
        } else {
            SettingsButtonRow(
                symbol: "person.crop.circle.badge.plus",
                accent: .oneDayBrand,
                title: Strings.signIn,
                caption: nil
            ) { showSignIn = true }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(OneDay.hairline).padding(.leading, 48)
    }

    /// An empty field means "I didn't mean to do that", not "call me nothing".
    private func commitName() {
        account.rename(to: draftName)
        draftName = account.account?.displayName ?? ""
    }

    /// Baked into the binary, so changing it costs a release: it points at the
    /// `1day.` subdomain rather than the apex, leaving the apex free for a
    /// personal site without ever breaking this link. App Store Connect must
    /// carry the same address.
    ///
    /// Locale-suffixed as of 1.3. The site made English its default that
    /// release — `/privacy` is the English page now and Chinese moved to
    /// `/zh/privacy` — so a fixed `/privacy` handed every Chinese reader a
    /// policy they can't read. This follows the language the app is actually
    /// being used in, not the device's, because that is the setting one screen
    /// above this link.
    static var privacyPolicyURL: URL {
        AppLanguage.effective == .chinese
            ? URL(string: "https://1day.liangyue.site/zh/privacy")!
            : URL(string: "https://1day.liangyue.site/privacy")!
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

}

// MARK: - Rows

/// The icon tile every settings row leads with. A real symbol, sized and
/// tinted the same way the moment card's rows are, so the two screens read as
/// the same app.
private struct SettingsIcon: View {
    let symbol: String
    let accent: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(accent)
            .frame(width: 28, height: 28)
            .background(accent.opacity(0.14), in: RoundedRectangle(
                cornerRadius: 9, style: .continuous))
    }
}

private struct SettingsToggleRow: View {
    let symbol: String
    let accent: Color
    let title: String
    /// The sentence that used to live in the section footer.
    let caption: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            SettingsIcon(symbol: symbol, accent: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.oneDayBrand)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct SettingsLinkRow<Destination: View>: View {
    let symbol: String
    let accent: Color
    let title: String
    /// What it's currently set to, so the row answers the question without
    /// being opened.
    let value: String
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 11) {
                SettingsIcon(symbol: symbol, accent: accent)
                Text(title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OneDay.inkFaint)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// A row that does something, or — with no action — just states a fact.
private struct SettingsButtonRow: View {
    let symbol: String
    let accent: Color
    let title: String
    let caption: String?
    var isDestructive = false
    var isDisabled = false
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.5 : 1)
                .accessibilityLabel(title)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 11) {
            SettingsIcon(symbol: symbol, accent: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(isDestructive ? Color.red : OneDay.ink)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OneDay.inkFaint)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
