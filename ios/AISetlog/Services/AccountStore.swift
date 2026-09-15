import Foundation
import AuthenticationServices
import UIKit
import Observation

/// The signed-in identity used to attribute clips in a shared room.
/// Sign in with Apple gives a stable `id` (per app) plus a display name.
/// Local-only ("just me") challenges never need this.
@Observable
final class AccountStore {
    struct Account: Codable {
        let id: String        // ASAuthorizationAppleIDCredential.user — stable per app
        /// Empty means "we don't know yet", not "this person is called nothing".
        /// The avatar layer is already built for that: `AvatarDot.hasName` tests
        /// `isEmpty`, so an empty name draws the mascot, and
        /// `Identity.uiColor(for:)` short-circuits to the brand blue instead of
        /// hashing a fake identity color. Storing a *placeholder word* here
        /// instead is what broke both — see `manufacturedNames`.
        var displayName: String

        /// The name, or nil when there isn't one — for the call sites that want
        /// to branch rather than print. Prefer this over comparing to `""`.
        var name: String? { displayName.isEmpty ? nil : displayName }
    }

    private static let key = "account.v1"

    /// Placeholder words that older builds persisted into `displayName` as if a
    /// user had chosen them. `completeSignIn` used to fall back to
    /// `Strings.defaultMemberName`, so whoever declined to share their Apple
    /// name got stored as literally "朋友" or "Friend" — which then rendered as
    /// a fake initial ("朋") over a real hashed identity color, and made two
    /// unnamed people in one room look like the same person.
    ///
    /// These are frozen historical literals **on purpose**: they must not be
    /// read from `Strings`, because the live copy is being changed and a lookup
    /// would stop matching the data already on disk.
    private static let manufacturedNames: Set<String> = ["朋友", "Friend"]

    /// Repairs a decoded account in place. Cheap enough to run on every load,
    /// and it has to be — the bad value is already persisted on every device
    /// that signed in without sharing a name.
    private static func sanitized(_ account: Account) -> Account {
        guard manufacturedNames.contains(account.displayName) else { return account }
        var fixed = account
        fixed.displayName = ""
        return fixed
    }
    /// In-process session epoch. Logging back into the same account must not
    /// revive work started before sign-out; a display-name change is not a login.
    private(set) static var identityRevision: UInt64 = 0

    static var persistedUserID: String? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let account = try? JSONDecoder().decode(Account.self, from: data)
        else { return nil }
        return account.id
    }

    private(set) var account: Account?
    var isSignedIn: Bool { account != nil }

    /// nil is an explicitly memory-only identity: no Apple validation, disk
    /// access, or mutation of the live chat session epoch.
    private let defaults: UserDefaults?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Account.self, from: data) {
            let repaired = Self.sanitized(saved)
            account = repaired
            // Write the repair back, so the placeholder stops travelling with
            // every clip this device uploads from here on.
            if repaired.displayName != saved.displayName { persist(repaired) }
            revalidate(saved.id)
        }
    }

    init(localIdentity: Account) {
        defaults = nil
        account = localIdentity
    }

    /// If the Apple ID credential was revoked (e.g. user signed out in Settings),
    /// drop the local account so we prompt again.
    private func revalidate(_ userID: String) {
        #if DEBUG
        // A debug tester isn't an Apple ID. Asking Apple about one comes back
        // `.notFound`, which would sign the tester out again on the next
        // launch — the identity would look like it never stuck.
        if userID.hasPrefix(Self.testerPrefix) { return }
        #endif
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            guard state == .revoked || state == .notFound else { return }
            Task { @MainActor in self?.signOut() }
        }
    }

    func signOut() {
        if defaults != nil { Self.identityRevision &+= 1 }
        account = nil
        defaults?.removeObject(forKey: Self.key)
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
            // stored name on later sign-ins; leave it empty when there is none.
            //
            // It used to fall back to `Strings.defaultMemberName`, which stored
            // a placeholder word as though the user had picked it. Empty is the
            // honest value: the avatar draws the mascot, and Settings shows an
            // empty field with its prompt, which is the only thing that tells
            // someone their name is still unset.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let resolved = name.isEmpty ? (account?.displayName ?? "") : name
            let acct = Account(id: credential.user, displayName: resolved)
            persist(acct)
            return acct
        }
    }

    /// Longer than this isn't a name, it's a caption — and it has to fit in a
    /// chip next to a clip.
    static let nameLimit = 24

    /// Apple sends the name exactly once, ever. Anyone who signed in before
    /// that stuck, or who declined to share it, is stuck being called whatever
    /// we guessed — in a room where their friends can see it. So it has to be
    /// editable, and that has been the whole reason to store it locally.
    ///
    /// Renaming is forward-only: clips already uploaded carry the name they
    /// were uploaded with, because rewriting other people's copies of the past
    /// is a bigger promise than a text field should make.
    func rename(to newName: String) {
        guard var updated = account, let name = Self.normalized(newName) else { return }
        updated.displayName = name
        persist(updated)
    }

    /// - Returns: the name to store, or `nil` when there's nothing usable in
    ///   the field. A cleared box means "never mind", not "call me nothing".
    static func normalized(_ raw: String) -> String? {
        let trimmed = String(
            raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
        return trimmed.isEmpty ? nil : trimmed
    }

#if DEBUG
    /// Sign in with Apple is unreliable on the simulator, which makes two-device
    /// room testing (the whole point of shared stories) hard to exercise. A
    /// debug build can mint a throwaway identity instead: the device name keeps
    /// the two testers apart, the UUID keeps their clip record names apart.
    static let testerPrefix = "tester-"

    func signInAsTester(named name: String? = nil) {
        persist(Account(
            id: Self.testerPrefix + UUID().uuidString,
            displayName: name ?? UIDevice.current.name))
    }
#endif

    private func persist(_ account: Account) {
        if defaults != nil, self.account?.id != account.id { Self.identityRevision &+= 1 }
        self.account = account
        if let defaults, let data = try? JSONEncoder().encode(account) {
            defaults.set(data, forKey: Self.key)
        }
    }

    enum SignInError: LocalizedError {
        case unexpectedCredential
        var errorDescription: String? { "Could not read your Apple ID." }
    }
}
