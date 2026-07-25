import SwiftUI
import UserNotifications

/// App-level language and notification preferences.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
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
                                challenge.title,
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
