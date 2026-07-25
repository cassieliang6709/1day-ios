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
                }
        }
    }
}

struct RootView: View {
    @Environment(ChallengeStore.self) private var store
    /// Join code parsed from an `oneday://join?code=XXXXXX` deep link.
    @State private var pendingJoinCode: String?

    var body: some View {
        RootShellView(pendingJoinCode: $pendingJoinCode)
            .onOpenURL { url in
                guard url.scheme == "oneday", url.host == "join",
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value
                else { return }
                pendingJoinCode = code
            }
    }
}
