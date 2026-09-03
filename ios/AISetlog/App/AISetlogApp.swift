import SwiftUI

@main
struct AISetlogApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @State private var account: AccountStore
    @State private var store: ChallengeStore
    @State private var drafts = ClipDraftStore()
    @State private var promptMetrics = PromptSuggestionMetrics()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system

    init() {
        let account = AccountStore()
        let store = ChallengeStore()
        store.account = account
        ReminderService.reconcile(for: store.challenges)
        SharedActivityNotificationService.reconcileSubscriptions(for: store.challenges)
        _account = State(initialValue: account)
        _store = State(initialValue: store)
        Self.settleGentleLook()
    }

    /// Put the look back to "as shot" unless you asked it to stick.
    ///
    /// Done here, before any view reads the key, so nothing gets one frame of
    /// yesterday's setting on the way to the right one.
    private static func settleGentleLook() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: GentleLook.storageKey)
            .flatMap(GentleLook.init(rawValue:)) ?? .none
        let sticky = defaults.bool(forKey: GentleLook.stickyKey)
        let opening = GentleLook.onLaunch(stored: stored, sticky: sticky)
        guard opening != stored else { return }
        defaults.set(opening.rawValue, forKey: GentleLook.storageKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(account)
                .environment(drafts)
                .environment(promptMetrics)
                .tint(Color.oneDayBlue)
                .preferredColorScheme(appAppearance.colorScheme)
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
                        homeLaunchAction = .quickStart
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
            guard let code = InviteCode.fromDeepLink(url) else { return }
            hasCompletedOnboarding = true
            pendingJoinCode = code
        }
    }
}
