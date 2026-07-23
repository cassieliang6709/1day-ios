import SwiftUI

@main
struct AISetlogApp: App {
    @State private var account: AccountStore
    @State private var store: ChallengeStore

    init() {
        let account = AccountStore()
        let store = ChallengeStore()
        store.account = account
        _account = State(initialValue: account)
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(account)
                .tint(Color.setlogBlue)
        }
    }
}

struct RootView: View {
    @Environment(ChallengeStore.self) private var store
    /// Join code parsed from an `aisetlog://join?code=XXXXXX` deep link.
    @State private var pendingJoinCode: String?

    var body: some View {
        HomeView(pendingJoinCode: $pendingJoinCode)
            .onOpenURL { url in
                guard url.scheme == "aisetlog", url.host == "join",
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value
                else { return }
                pendingJoinCode = code
            }
    }
}
