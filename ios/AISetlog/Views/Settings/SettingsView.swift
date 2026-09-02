import SwiftUI
import UserNotifications

/// App-level language and notification preferences.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account

    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    /// Held locally so a half-typed name never reaches the rooms.
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
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

                Section {
                    Picker(Strings.appearance, selection: $appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.displayName).tag(appearance)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(Strings.appearance)
                } footer: {
                    Text(Strings.appearanceFootnote)
                }

                Section {
                    Toggle(
                        Strings.eveningReminder,
                        isOn: Binding(
                            get: { eveningEnabled },
                            set: setEveningEnabled))
                    if eveningEnabled {
                        DatePicker(
                            Strings.reminderTime,
                            selection: reminderTime,
                            displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text(Strings.notifications)
                } footer: {
                    Text(Strings.eveningReminderFooter)
                }

                Section {
                    Toggle(
                        Strings.friendActivity,
                        isOn: Binding(
                            get: { sharedEnabled },
                            set: setSharedEnabled))
                    if sharedEnabled {
                        Toggle(Strings.showFriendNames, isOn: $showFriendNames)
                    }
                } footer: {
                    Text(Strings.friendActivityFooter)
                }

                if sharedEnabled && !sharedChallenges.isEmpty {
                    Section(Strings.sharedRooms) {
                        ForEach(sharedChallenges) { challenge in
                            Toggle(
                                ChallengePresenter(challenge: challenge).displayTitle,
                                isOn: roomEnabledBinding(for: challenge))
                        }
                    }
                }

                if authorizationStatus == .denied
                    && (eveningEnabled || sharedEnabled) {
                    Section {
                        Text(Strings.notificationPermissionDenied)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(Strings.openSettings) {
                            guard let url = URL(
                                string: UIApplication.openSettingsURLString)
                            else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }
                accountSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
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
        }
        .presentationDetents([.medium, .large])
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
                Button(Strings.signOut) { account.signOut() }
            } else {
                Text(Strings.notSignedIn)
                    .foregroundStyle(.secondary)
            }

            Button(Strings.deleteAccount, role: .destructive) {
                showDeleteConfirmation = true
            }
            .disabled(isDeleting)
        } header: {
            Text(Strings.account)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if account.isSignedIn { Text(Strings.yourNameFootnote) }
                Text(Strings.deleteAccountFootnote)
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
                    await store.deleteAccountAndAllData()
                    isDeleting = false
                    dismiss()
                }
            }
            Button(Strings.cancel, role: .cancel) {}
        } message: {
            Text(Strings.deleteAccountWarning)
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

#if DEBUG
    /// Not localized, like the rest of the debug affordances: the audience is
    /// whoever is building the thing.
    private var debugSection: some View {
        Section {
            Button("Open a demo room") {
                DemoRoom.seed(into: store)
                dismiss()
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("A shared room with two friends, their clips and reactions already in it — made on this device. No iCloud, no second phone. It appears at the top of the home screen. Filming in it works; nothing leaves the device.")
        }
    }
#endif

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

    private func roomEnabledBinding(for challenge: Challenge) -> Binding<Bool> {
        Binding {
            guard let code = challenge.roomCode else { return false }
            return !mutedRooms.contains(code)
        } set: { enabled in
            guard let code = challenge.roomCode else { return }
            NotificationPreferences.setRoom(code, muted: !enabled)
            mutedRooms = NotificationPreferences.mutedRoomCodes
            SharedActivityNotificationService.reconcileSubscriptions(
                for: store.challenges)
        }
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }
}
