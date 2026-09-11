import SwiftUI
import UserNotifications

/// App-level preferences: notifications, display and language, the account,
/// and the small print. Anything with more than a couple of options is a row
/// here and a page behind it — see `body`.
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

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
    /// Read, not written, here: the row shows which look is on and the page
    /// behind it does the setting.
    @AppStorage(PersonalEffectParameters.storageKey) private var look: PersonalEffectParameters = .none
    @AppStorage(NotificationPreferences.eveningEnabledKey)
    private var eveningEnabled = false
    @AppStorage(NotificationPreferences.sharedEnabledKey)
    private var sharedEnabled = false
    @AppStorage(NotificationPreferences.showFriendNamesKey)
    private var showFriendNames = false

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var mutedRooms = NotificationPreferences.mutedRoomCodes

    private var sharedChallenges: [Challenge] {
        var seen: Set<String> = []
        return store.challenges.filter { challenge in
            guard let code = challenge.roomCode, seen.insert(code).inserted else {
                return false
            }
            return true
        }
    }

    /// Four titled groups, in the order you'd go looking for them: the switches
    /// you actually flip, the things you set once, who you are, and the legal
    /// small print.
    ///
    /// It used to be nine sections, three of them untitled, with every option
    /// of three pickers spelled out on the front page — the medium detent
    /// couldn't show past "Appearance". Notifications alone were spread over
    /// four sections that had nothing between them but a gap.
    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                displaySection
                accountSection
                aboutSection
            }
            .navigationTitle(Strings.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
            .task {
                await refreshAuthorizationStatus()
                mutedRooms = NotificationPreferences.mutedRoomCodes
            }
            // On the Form, not on the Section: a sheet presented from inside a
            // Section of an already-presented sheet takes the whole settings
            // panel down with it.
            .sheet(isPresented: $showSignIn) {
                SignInView { showSignIn = false }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Notifications

    /// Everything that can make this app interrupt you, under one heading. The
    /// two switches stay here because they're what people come to change; the
    /// room-by-room list is one tap down because it's as long as the number of
    /// rooms you're in, and the "iPhone says no" notice only appears when it's
    /// true of something you just asked for.
    @ViewBuilder
    private var notificationSection: some View {
        Section {
            Toggle(
                Strings.eveningReminder,
                isOn: Binding(get: { eveningEnabled }, set: setEveningEnabled))
            if eveningEnabled {
                DatePicker(
                    Strings.reminderTime,
                    selection: reminderTime,
                    displayedComponents: .hourAndMinute)
            }

            Toggle(
                Strings.friendActivity,
                isOn: Binding(get: { sharedEnabled }, set: setSharedEnabled))
            if sharedEnabled {
                Toggle(Strings.showFriendNames, isOn: $showFriendNames)

                if !sharedChallenges.isEmpty {
                    NavigationLink {
                        RoomNotificationsView(
                            rooms: sharedChallenges, mutedRooms: $mutedRooms)
                    } label: {
                        LabeledContent(
                            Strings.sharedRooms,
                            value: RoomNotificationsView.summary(
                                rooms: sharedChallenges, muted: mutedRooms))
                    }
                }
            }

            if authorizationStatus == .denied && (eveningEnabled || sharedEnabled) {
                Text(Strings.notificationPermissionDenied)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(Strings.openSettings) {
                    guard let url = URL(string: UIApplication.openSettingsURLString)
                    else { return }
                    UIApplication.shared.open(url)
                }
            }
        } header: {
            Text(Strings.notifications)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.eveningReminderFooter)
                Text(Strings.friendActivityFooter)
            }
        }
    }

    // MARK: - Display & language

    /// Three decisions you make once and forget. One line each, showing what
    /// it's currently set to; the options and the sentence explaining them are
    /// on the screen behind the row.
    ///
    /// The look dials are deliberately not here, on this page or the one behind
    /// it — a dial you can't see the effect of is a dial you're guessing at, so
    /// fine-tuning stays on the screen with the picture on it.
    private var displaySection: some View {
        Section {
            NavigationLink {
                LookSettingsView()
            } label: {
                LabeledContent(
                    Strings.lookSetting, value: LookSettingsView.summary(for: look))
            }

            NavigationLink {
                SettingsOptionPage(
                    title: Strings.appearance,
                    footnote: Strings.appearanceFootnote,
                    selection: $appAppearance)
            } label: {
                LabeledContent(Strings.appearance, value: appAppearance.displayName)
            }

            NavigationLink {
                SettingsOptionPage(
                    title: Strings.language,
                    footnote: Strings.languageFootnote,
                    selection: $appLanguage)
            } label: {
                LabeledContent(Strings.language, value: appLanguage.displayName)
            }
        } header: {
            Text(Strings.displayAndLanguage)
        }
    }

    // MARK: - Account

    /// Sign out and delete. Both were missing entirely: `signOut()` existed on
    /// `AccountStore` but nothing in the UI ever called it, and there was no
    /// way at all to delete an account — which App Store guideline 5.1.1(v)
    /// requires of any app that creates one.
    @ViewBuilder
    private var accountSection: some View {
        Section {
            if account.isSignedIn {
                LabeledContent(Strings.yourNameLabel) {
                    TextField(Strings.yourNamePlaceholder, text: $draftName)
                        .multilineTextAlignment(.trailing)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(commitName)
                        .accessibilityIdentifier("your-name")
                }
                .onChange(of: nameFocused) { _, focused in
                    if !focused { commitName() }
                }
                // Through the store, not straight at the account: the rooms
                // hold a cache keyed by who I am.
                Button(Strings.signOut) { store.signOut() }

                // Only an account that exists can be deleted. Offering this
                // while signed out put a button that erases every story on
                // the device under a heading nobody reads as "erase my
                // stories" — and there was nothing there to delete anyway.
                Button(Strings.deleteAccount, role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(isDeleting)
            } else {
                Text(Strings.notSignedIn)
                    .foregroundStyle(.secondary)

                // Signing out used to be one-way from this screen: the only
                // other sign-in gate is the one in front of a shared story,
                // so getting back in meant starting one.
                Button(Strings.signIn) { showSignIn = true }
            }
        } header: {
            Text(Strings.account)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if account.isSignedIn {
                    Text(Strings.yourNameFootnote)
                    Text(Strings.deleteAccountFootnote)
                }
            }
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
                        // Nothing local has been touched, so there is something
                        // to come back to. Saying "try again" is only honest
                        // because of that ordering.
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

    /// An empty field means "I didn't mean to do that", not "call me nothing".
    private func commitName() {
        account.rename(to: draftName)
        draftName = account.account?.displayName ?? ""
    }


    private var aboutSection: some View {
        Section {
            Link(Strings.privacyPolicy, destination: Self.privacyPolicyURL)
            LabeledContent(Strings.version, value: Self.versionString)
        } header: {
            Text(Strings.about)
        }
    }

    /// Baked into the binary, so changing it costs a release: it points at the
    /// `1day.` subdomain rather than the apex, leaving the apex free for a
    /// personal site without ever breaking this link. App Store Connect must
    /// carry the same address.
    static let privacyPolicyURL = URL(string: "https://1day.liangyue.site/privacy")!

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: NotificationPreferences.eveningHour,
                minute: NotificationPreferences.eveningMinute,
                second: 0,
                of: .now) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            NotificationPreferences.eveningHour = components.hour ?? 20
            NotificationPreferences.eveningMinute = components.minute ?? 30
            ReminderService.reconcile(for: store.challenges)
        }
    }

    private func setEveningEnabled(_ enabled: Bool) {
        guard enabled else {
            eveningEnabled = false
            ReminderService.reconcile(for: store.challenges)
            return
        }
        Task {
            let granted = await NotificationPermissionService.requestAuthorization()
            eveningEnabled = granted
            NotificationPreferences.primerSeen = true
            await refreshAuthorizationStatus()
            ReminderService.reconcile(for: store.challenges)
        }
    }

    private func setSharedEnabled(_ enabled: Bool) {
        guard enabled else {
            sharedEnabled = false
            SharedActivityNotificationService.removeSubscriptions()
            return
        }
        Task {
            let granted = await NotificationPermissionService.requestAuthorization()
            sharedEnabled = granted
            await refreshAuthorizationStatus()
            if granted {
                NotificationPermissionService.registerForRemoteNotificationsIfNeeded()
            }
            SharedActivityNotificationService.reconcileSubscriptions(
                for: store.challenges)
        }
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }
}
