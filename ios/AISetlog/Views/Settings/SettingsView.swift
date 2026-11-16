import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account

    @State private var showDeleteConfirmation = false
    @State private var deleteFailed = false
    @State private var isDeleting = false
    @State private var showSignIn = false
    @State private var signInError: String?
    @State private var showAvatarSetup = false
    @State private var showAvatarPreview = false
    @State private var retakeAfterPreview = false
    @State private var avatarPreviewHeight: CGFloat = 420
    @State private var showSignOutConfirmation = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool


    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
    @AppStorage(AppSkin.storageKey) private var appSkin: AppSkin = .cream

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
                        let service = AccountDeletionService(store: store)
                        let gone = await service.run()
                        isDeleting = false
                        if gone {
                            dismiss()
                        } else {
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
        .presentationDetents([.large])
    }


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
                    HStack(spacing: 7) {
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


    @ViewBuilder
    private var displayRows: some View {
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

    private func commitName() {
        account.rename(to: draftName)
        draftName = account.account?.displayName ?? ""
    }

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
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

#if DEBUG
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
