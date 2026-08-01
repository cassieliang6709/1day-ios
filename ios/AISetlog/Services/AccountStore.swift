import Foundation
import AuthenticationServices
import Observation

/// The signed-in identity used to attribute clips in a shared room.
/// Sign in with Apple gives a stable `id` (per app) plus a display name.
/// Local-only ("just me") challenges never need this.
@Observable
final class AccountStore {
    struct Account: Codable {
        let id: String        // ASAuthorizationAppleIDCredential.user — stable per app
        var displayName: String
    }

    private static let key = "account.v1"

    static var persistedUserID: String? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let account = try? JSONDecoder().decode(Account.self, from: data)
        else { return nil }
        return account.id
    }

    private(set) var account: Account?
    var isSignedIn: Bool { account != nil }

    init() {
        #if DEBUG
        // Simulator helper: Sign in with Apple can't run there, so a
        // signed-in-shaped state is otherwise unreachable — and several
        // layout paths only appear once there's a display name.
        // `-demoAccountName "悦 梁"`
        if let name = UserDefaults.standard.string(forKey: "demoAccountName"),
           !name.isEmpty {
            account = Account(id: "demo-account", displayName: name)
            return
        }
        #endif
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Account.self, from: data) {
            account = saved
            revalidate(saved.id)
        }
    }

    /// If the Apple ID credential was revoked (e.g. user signed out in Settings),
    /// drop the local account so we prompt again.
    private func revalidate(_ userID: String) {
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            guard state == .revoked || state == .notFound else { return }
            Task { @MainActor in self?.signOut() }
        }
    }

    func signOut() {
        account = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    // MARK: - Sign in with Apple (driven by SignInWithAppleButton)

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    /// Parse and persist the button's result. Returns the account on success.
    @discardableResult
    func completeSignIn(_ result: Result<ASAuthorization, Error>) throws -> Account {
        switch result {
        case .failure(let error):
            throw error
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw SignInError.unexpectedCredential
            }
            // Apple only sends the name on the FIRST sign-in ever. Reuse the
            // stored name on later sign-ins; fall back to a friendly default.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let resolved = name.isEmpty ? (account?.displayName ?? "Friend") : name
            let acct = Account(id: credential.user, displayName: resolved)
            persist(acct)
            return acct
        }
    }

    private func persist(_ account: Account) {
        self.account = account
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    enum SignInError: LocalizedError {
        case unexpectedCredential
        var errorDescription: String? { "Could not read your Apple ID." }
    }
}
