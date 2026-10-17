import SwiftUI

@main
struct AISetlogApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @State private var account: AccountStore
    @State private var store: ChallengeStore
    @State private var drafts = ClipDraftStore()
    @State private var moods = MoodStore()
    @State private var promptMetrics = PromptSuggestionMetrics()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
    /// The accent the whole app wears, which is whichever colour you picked for
    /// your avatar. Bound so `.tint` below is handed the new one the moment it
    /// changes.
    @AppStorage(Identity.myTintKey) private var myTintIndex = -1
    /// Picking a skin rebuilds the tree (`.id` below). A new `.tint` alone
    /// only reached views that read the tint; the canvas and the plain-text
    /// labels kept the old skin. The rebuild closes the Settings sheet it was
    /// picked in, so Settings sets `AppSkin.reopenSettingsKey` and the home
    /// screen opens it again.
    @AppStorage(AppSkin.storageKey) private var appSkin: AppSkin = .cream

    init() {
        let account = AccountStore()
        let store = ChallengeStore()
        store.account = account
        ReminderService.reconcile(for: store.challenges)
        SharedActivityNotificationService.reconcileSubscriptions(for: store.challenges)
        _account = State(initialValue: account)
        _store = State(initialValue: store)
        Self.settlePersonalEffect()
    }

    /// Put the grade back to "as shot" unless you asked it to stick.
    ///
    /// Done here, before any view reads the key, so nothing gets one frame of
    /// yesterday's setting on the way to the right one.
    private static func settlePersonalEffect() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: PersonalEffectParameters.storageKey)
            .flatMap(PersonalEffectParameters.init(rawValue:)) ?? .none
        let sticky = defaults.bool(forKey: PersonalEffectParameters.stickyKey)
        let opening = PersonalEffectParameters.onLaunch(stored: stored, sticky: sticky)
        guard opening != stored else { return }
        defaults.set(opening.rawValue, forKey: PersonalEffectParameters.storageKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(appSkin)
                .environment(store)
                .environment(account)
                .environment(drafts)
                .environment(moods)
                .environment(promptMetrics)
                // `.tint` is enough on its own: it is an environment value, so
                // changing it invalidates the whole subtree and every screen
                // re-reads `Color.oneDayBrand`. An `.id(myTintIndex)` here also
                // worked, and rebuilt the tree so hard that it closed the
                // Settings sheet you were picking the colour in.
                // `brandText`, not the fill colour: the system draws plain
                // buttons and links in the tint, and 奶油黄 can't be text.
                .tint(OneDay.brandText)
                .preferredColorScheme(appAppearance.colorScheme)
                // Runs on launch and on every skin change; outside `.id` so
                // the rebuild doesn't re-trigger it.
                .task(id: appSkin) { AppSkin.syncAppIcon(to: appSkin) }
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
