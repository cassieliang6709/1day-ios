import SwiftUI

@main
struct AISetlogApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @State private var account: AccountStore
    @State private var store: ChallengeStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let account = AccountStore()
        let store = ChallengeStore()
        store.account = account
        ReminderService.reconcile(for: store.challenges)
        SharedActivityNotificationService.reconcileSubscriptions(for: store.challenges)
        _account = State(initialValue: account)
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(account)
                .tint(Color.oneDayBlue)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    ReminderService.reconcile(for: store.challenges)
                    SharedActivityNotificationService.reconcileSubscriptions(
                        for: store.challenges)
                    NotificationPermissionService.registerForRemoteNotificationsIfNeeded()
                    Task { await store.syncSharedRooms() }
                }
        }
    }
}

struct RootView: View {
    @Environment(ChallengeStore.self) private var store
    /// Join code parsed from an `oneday://join?code=XXXXXX` deep link.
    @State private var pendingJoinCode: String?
    @State private var homeLaunchAction: HomeLaunchAction?
    @AppStorage("onboarding.completed.v1") private var hasCompletedOnboarding = false
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var needsOnboarding: Bool {
        !hasCompletedOnboarding && store.challenges.isEmpty
    }

    var body: some View {
        Group {
            if needsOnboarding {
                FirstRunOnboardingView(
                    onCreateStory: {
                        hasCompletedOnboarding = true
                        homeLaunchAction = .newStory
                    },
                    onJoin: {
                        hasCompletedOnboarding = true
                        homeLaunchAction = .join
                    })
            } else {
                RootShellView(
                    pendingJoinCode: $pendingJoinCode,
                    launchAction: $homeLaunchAction)
            }
        }
        .environment(\.locale, appLanguage.resolved.locale)
        .onAppear {
            // Existing installs should never be sent through first-run screens
            // merely because this version introduced onboarding.
            if !store.challenges.isEmpty {
                hasCompletedOnboarding = true
            }
        }
        .onOpenURL { url in
            guard url.scheme == "oneday", url.host == "join",
                  let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value
            else { return }
            hasCompletedOnboarding = true
            pendingJoinCode = code
        }
    }
}
