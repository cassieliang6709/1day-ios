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

    /// Who you are, what you've made, then the switches.
    ///
    /// This screen has been through two rewrites of its *structure* — nine
    /// sections down to four — and both times it stayed a stock `Form`, which
    /// made it the one page in the app rendered in system greys and system
    /// blue. Coming here from the home screen felt like leaving the app.
    ///
    /// So: the app's own canvas and glass cards, and a header that answers
    /// "who am I here" before it offers anything to change. The three counts
    /// are the only new content, and they're the only reason to open this page
    /// when you don't want to change a setting.
    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        identityHeader
                        statsRow
                        group(Strings.notifications, rows: notificationRows)
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
            .task {
                await refreshAuthorizationStatus()
                mutedRooms = NotificationPreferences.mutedRoomCodes
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
                        .tint(Color.oneDayBlue)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(commitName)
                        .accessibilityIdentifier("your-name")
                    Text(nameFocused ? Strings.yourNameFootnote : Strings.tapToRename)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                        .lineLimit(2)
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
                        .foregroundStyle(Color.oneDayBlue)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
                .foregroundStyle(Color.oneDayBlue)
            Text("·")
            Text(Self.versionString)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(OneDay.inkFaint)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: - Notifications

    /// Everything that can make this app interrupt you, under one heading. The
    /// two switches stay here because they're what people come to change; the
    /// room-by-room list is one tap down because it's as long as the number of
    /// rooms you're in, and the "iPhone says no" notice only appears when it's
    /// true of something you just asked for.
    ///
    /// The `footer` sentences the old `Section` carried are now each row's own
    /// second line, where they sit next to the switch they explain instead of
    /// in a paragraph under three unrelated ones.
    @ViewBuilder
    private var notificationRows: some View {
        SettingsToggleRow(
            symbol: "moon.stars.fill",
            accent: .oneDayBlue,
            title: Strings.eveningReminder,
            caption: Strings.eveningReminderFooter,
            isOn: Binding(get: { eveningEnabled }, set: setEveningEnabled))

        if eveningEnabled {
            rowDivider
            HStack {
                DatePicker(
                    Strings.reminderTime,
                    selection: reminderTime,
                    displayedComponents: .hourAndMinute)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
        }

        rowDivider
        SettingsToggleRow(
            symbol: "person.2.fill",
            accent: .oneDayLavender,
            title: Strings.friendActivity,
            caption: Strings.friendActivityFooter,
            isOn: Binding(get: { sharedEnabled }, set: setSharedEnabled))

        if sharedEnabled {
            rowDivider
            SettingsToggleRow(
                symbol: "tag.fill",
                accent: .oneDayMint,
                title: Strings.showFriendNames,
                caption: nil,
                isOn: $showFriendNames)

            if !sharedChallenges.isEmpty {
                rowDivider
                SettingsLinkRow(
                    symbol: "bell.badge.fill",
                    accent: .oneDayLavender,
                    title: Strings.sharedRooms,
                    value: RoomNotificationsView.summary(
                        rooms: sharedChallenges, muted: mutedRooms)
                ) {
                    RoomNotificationsView(rooms: sharedChallenges, mutedRooms: $mutedRooms)
                }
            }
        }

        if authorizationStatus == .denied && (eveningEnabled || sharedEnabled) {
            rowDivider
            VStack(alignment: .leading, spacing: 7) {
                Text(Strings.notificationPermissionDenied)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(Strings.openSettings) {
                    guard let url = URL(string: UIApplication.openSettingsURLString)
                    else { return }
                    UIApplication.shared.open(url)
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.oneDayBlue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
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
    @ViewBuilder
    private var displayRows: some View {
        SettingsLinkRow(
            symbol: "wand.and.sparkles",
            accent: .oneDayMint,
            title: Strings.lookSetting,
            value: LookSettingsView.summary(for: look)
        ) {
            LookSettingsView()
        }
        rowDivider
        SettingsLinkRow(
            symbol: "circle.lefthalf.filled",
            accent: .oneDayNavy,
            title: Strings.appearance,
            value: appAppearance.displayName
        ) {
            SettingsOptionPage(
                title: Strings.appearance,
                footnote: Strings.appearanceFootnote,
                selection: $appAppearance)
        }
        rowDivider
        SettingsLinkRow(
            symbol: "globe",
            accent: .oneDayBlue,
            title: Strings.language,
            value: appLanguage.displayName
        ) {
            SettingsOptionPage(
                title: Strings.language,
                footnote: Strings.languageFootnote,
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
                caption: Strings.deleteAccountFootnote,
                isDestructive: true,
                isDisabled: isDeleting
            ) { showDeleteConfirmation = true }
        } else {
            SettingsButtonRow(
                symbol: "person.crop.circle.badge.plus",
                accent: .oneDayBlue,
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
                .tint(Color.oneDayBlue)
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
