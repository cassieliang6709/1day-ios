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
    @State private var signInError: String?
    @State private var showAvatarSetup = false
    @State private var showAvatarPreview = false
    /// 重拍 asks for the setup flow; the sheet's `onDismiss` opens it once the
    /// preview is really gone. A fixed delay raced the dismissal animation.
    @State private var retakeAfterPreview = false
    /// The preview sheet sizes to its content instead of a half-screen detent
    /// with empty space under the button.
    @State private var avatarPreviewHeight: CGFloat = 420
    /// Signing out hides every shared room on this device, which nothing on
    /// the row itself suggests — so it asks first.
    @State private var showSignOutConfirmation = false
    /// Held locally so a half-typed name never reaches the rooms.
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    /// Written by the picker below, read by every `AvatarDot` — held here too
    /// so this screen repaints its own header the moment a dot is tapped.

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
    @AppStorage(AppSkin.storageKey) private var appSkin: AppSkin = .cream

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
                    .onChange(of: appSkin) { _, _ in
                        UserDefaults.standard.set(true, forKey: AppSkin.reopenSettingsKey)
                    }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        identityHeader
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
            .sheet(isPresented: $showAvatarPreview, onDismiss: {
                guard retakeAfterPreview else { return }
                retakeAfterPreview = false
                showAvatarSetup = true
            }) { avatarPreview }
            .fullScreenCover(isPresented: $showAvatarSetup) {
                AvatarSetupFlow(onFinish: { _ in showAvatarSetup = false }, skipLabel: Strings.cancel)
            }
            .onAppear { draftName = account.account?.displayName ?? "" }
            .onChange(of: account.account?.displayName) { _, name in
                guard !nameFocused else { return }
                draftName = name ?? ""
            }
            .confirmationDialog(
                Strings.signOutConfirmTitle,
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                // Through the store, not straight at the account: the rooms
                // hold a cache keyed by who I am.
                Button(Strings.signOut, role: .destructive) { store.signOut() }
                Button(Strings.cancel, role: .cancel) {}
            } message: {
                Text(Strings.signOutConfirmMessage)
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

    @ViewBuilder
    private var identityHeader: some View {
        if account.isSignedIn {
            VStack(alignment: .leading, spacing: 11) {
                identityRow
            }
            .padding(.vertical, 4)
        } else {
            signedOutCard
        }
    }

    /// Signed out, the top of settings is a whole card saying what that costs,
    /// with the Apple button itself on it. It used to be 「未登录」 and a small
    /// 「登录」 link, easy to miss after the app signed itself out.
    private var signedOutCard: some View {
        VStack(spacing: 0) {
            Image("OneDayMascotCream")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            Text(Strings.signedOutTitle)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .padding(.bottom, 4)
            Text(Strings.signedOutSettingsBody)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
            AppleSignInButton(height: 46) { signInError = nil } onError: { signInError = $0 }
                .clipShape(Capsule())
                .accessibilityIdentifier("settings-sign-in")
            GoogleAccountButton { signInError = nil } onError: { signInError = $0 }
                .padding(.top, 10)
            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .glassSurface(radius: 22)
    }

    /// Your current photo, full size, with 重拍 under it.
    ///
    /// The cut-out drawn straight on the sheet rather than through
    /// `AvatarDot`: the dot fills white behind a photo, which at this size was
    /// a bright disc on the dark sheet. The small dots elsewhere keep it.
    private var avatarPreview: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                IconBubble(systemName: "xmark", label: Strings.close) {
                    showAvatarPreview = false
                }
            }
            if let image = AvatarStore.shared.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .accessibilityLabel(Strings.avatarAccessibility)
            }
            Button(Strings.retake) {
                retakeAfterPreview = true
                showAvatarPreview = false
            }
            .buttonStyle(.primaryAction)
            .frame(width: 200)
            .accessibilityIdentifier("avatar-retake")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { avatarPreviewHeight = $0 }
        .presentationDetents([.height(avatarPreviewHeight)])
        .presentationDragIndicator(.visible)
    }

    private var identityRow: some View {
        HStack(spacing: 13) {
            // Tapping your own face redraws your avatar.
            Button {
                if AvatarStore.shared.image != nil { showAvatarPreview = true } else { showAvatarSetup = true }
            } label: {
                AvatarDot(name: account.account?.displayName, size: 54, image: AvatarStore.shared.image)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.avatarAccessibility)
            .accessibilityHint(Strings.avatarRedoHint)
            .accessibilityIdentifier("settings-avatar")

            if account.isSignedIn {
                VStack(alignment: .leading, spacing: 2) {
                    // The name is editable in place, which is what makes the
                    // caption under it true. It was a right-aligned text field
                    // in a row called "Your name", three groups further down.
                    // The pencil is the only sign a heavy-weight name is a
                    // field; without it nobody thought to tap it.
                    HStack(spacing: 7) {
                        // `fixedSize` on a TextField doesn't hug its text, so
                        // the pencil drifted to the middle of the row. A hidden
                        // Text of the same string sets the width instead.
                        Text(draftName.isEmpty ? Strings.yourNamePlaceholder : draftName)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .padding(.trailing, 2)
                            .hidden()
                            .overlay(alignment: .leading) {
                                TextField(Strings.yourNamePlaceholder, text: $draftName)
                                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                                    .foregroundStyle(OneDay.ink)
                                    .tint(Color.oneDayBrand)
                                    .focused($nameFocused)
                                    .submitLabel(.done)
                                    .onSubmit(commitName)
                                    .accessibilityIdentifier("your-name")
                                    .accessibilityHint(Strings.editNameHint)
                            }
                        if !nameFocused {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(OneDay.inkFaint)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                                .onTapGesture { nameFocused = true }
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .onChange(of: nameFocused) { _, focused in
                    if !focused { commitName() }
                }
            }

            Spacer(minLength: 0)
        }
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
                .foregroundStyle(OneDay.brandText)
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
            accent: OneDay.brandText,
            title: Strings.appearance,
            value: appAppearance.displayName
        ) {
            SettingsOptionPage(
                title: Strings.appearance,
                selection: $appAppearance)
        }
        rowDivider
        SettingsLinkRow(
            symbol: "paintpalette",
            accent: OneDay.brandText,
            title: Strings.skinTitle,
            value: appSkin.displayName
        ) {
            SettingsOptionPage(
                title: Strings.skinTitle,
                selection: $appSkin)
        }
        rowDivider
        SettingsLinkRow(
            symbol: "globe",
            accent: OneDay.brandText,
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
            SettingsButtonRow(
                symbol: "rectangle.portrait.and.arrow.right",
                accent: .oneDayNavy,
                title: Strings.signOut,
                caption: nil
            ) { showSignOutConfirmation = true }
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
            // No chevron: these rows do something on the spot. A chevron
            // promises another screen, and 退出登录 doesn't have one.
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

#if DEBUG
/// 创建测试房间: a real room in the CloudKit development database with two
/// fake friends' clips in it. See `DebugTestRoom`.
private struct DebugTestRoomRows: View {
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account

    @State private var creating = false
    @State private var created: Challenge?
    @State private var message: String?

    var body: some View {
        SettingsButtonRow(
            symbol: "testtube.2",
            accent: .oneDayNavy,
            title: creating ? Strings.debugCreatingTestRoom : Strings.debugCreateTestRoom,
            caption: message ?? Strings.debugTestRoomCaption,
            isDisabled: creating,
            action: create)
            .accessibilityIdentifier("settings-debug-create-test-room")
        if let created {
            RoomInviteCodeCard(challenge: created)
        }
    }

    private func create() {
        guard account.isSignedIn else {
            message = Strings.debugTestRoomNeedsSignIn
            return
        }
        creating = true
        message = nil
        Task {
            defer { creating = false }
            do {
                created = try await DebugTestRoom.create(in: store)
                message = Strings.debugTestRoomCreated
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
#endif
