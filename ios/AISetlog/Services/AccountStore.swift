import Foundation
import AuthenticationServices
import GoogleSignIn
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
    /// Whether the Worker has given this phone a session for `account`.
    /// Without one nothing shared works, so the person counts as signed out
    /// — the id and name stay, so signing in again as the same person picks
    /// up exactly where they were.
    private(set) var hasSession: Bool
    var isSignedIn: Bool {
        guard let account else { return false }
        #if DEBUG
        if account.id.hasPrefix(Self.testerPrefix) { return true }
        #endif
        return hasSession
    }

    /// nil is an explicitly memory-only identity: no Apple validation, disk
    /// access, or mutation of the live chat session epoch.
    private let defaults: UserDefaults?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasSession = SessionKeychain.standard.load().map { $0.expiresAt > .now } ?? false
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Account.self, from: data) {
            let repaired = Self.sanitized(saved)
            account = repaired
            // Write the repair back, so the placeholder stops travelling with
            // every clip this device uploads from here on.
            if repaired.displayName != saved.displayName { persist(repaired) }
            revalidate(saved.id)
            if !hasSession { restoreGoogleSession(for: saved.id) }
        }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: .oneDaySessionEnded, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hasSession = false
        }
    }

    init(localIdentity: Account) {
        defaults = nil
        account = localIdentity
        hasSession = true
    }

    deinit {
        if let sessionObserver { NotificationCenter.default.removeObserver(sessionObserver) }
    }

    @ObservationIgnored private var sessionObserver: NSObjectProtocol?

    /// If the Apple ID credential was revoked (e.g. user signed out in Settings),
    /// drop the local account so we prompt again.
    private func revalidate(_ userID: String) {
        #if DEBUG
        // A debug tester isn't an Apple ID. Asking Apple about one comes back
        // `.notFound`, which would sign the tester out again on the next
        // launch — the identity would look like it never stuck.
        if userID.hasPrefix(Self.testerPrefix) { return }
        #endif
        // Apple has never heard of a Google account.
        if userID.hasPrefix(Self.googlePrefix) { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            guard Self.signsOut(on: state) else { return }
            Task { @MainActor in self?.signOut() }
        }
    }

    /// Revoked is the one answer that means "this person stopped using Sign in
    /// with Apple here". `.notFound` came back for accounts signed in on 1Day
    /// Dev — its own bundle — and signing out on it dropped the session after
    /// launch, leaving every room without friends' clips or members.
    static func signsOut(on state: ASAuthorizationAppleIDProvider.CredentialState) -> Bool {
        state == .revoked
    }

    func signOut() {
        if defaults != nil {
            Self.identityRevision &+= 1
            // While the session still exists to say who is asking.
            SharedActivityNotificationService.removeSubscriptions(session: SessionKeychain.standard.load())
            SessionKeychain.standard.delete()
            GIDSignIn.sharedInstance.signOut()
        }
        hasSession = false
        account = nil
        defaults?.removeObject(forKey: Self.key)
    }

    // MARK: - Sign in with Apple (driven by SignInWithAppleButton)

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    /// Parse the button's result, trade it for a 1Day session and persist
    /// both. Returns the account on success; nothing is stored on failure.
    @discardableResult
    func completeSignIn(_ result: Result<ASAuthorization, Error>) async throws -> Account {
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
            try await signIn(
                acct, .apple,
                identityToken: credential.identityToken.flatMap { String(data: $0, encoding: .utf8) })
            return acct
        }
    }

    // MARK: - Google

    /// Google account ids get this in front so they can never collide with an
    /// Apple one, and so `revalidate` knows not to ask Apple about them.
    static let googlePrefix = "google:"

    /// Opens Google's sign-in over whatever is on screen (a sheet, usually).
    /// Throws `GIDSignInError.canceled` when the person backs out.
    @MainActor
    func signInWithGoogle() async throws {
        guard let presenter = Self.topViewController() else { throw SignInError.unexpectedCredential }
        let user = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter).user
        guard let googleID = user.userID else { throw SignInError.unexpectedCredential }
        let id = Self.googlePrefix + googleID
        // Google sends the name every time; a name changed in Settings since
        // then is the one to keep.
        let kept = account?.id == id ? account?.name : nil
        let name = kept ?? Self.normalized(user.profile?.name ?? "") ?? ""
        try await signIn(
            Account(id: id, displayName: name), .google, identityToken: user.idToken?.tokenString)
    }

    /// The view controller to present Google's sheet from: the top of
    /// whatever chain of sheets is showing, since presenting from one that is
    /// already presenting does nothing.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - 1Day session

    /// Trades the provider's token for 1Day's own and only then stores the
    /// account: without a session nothing shared works, so a Worker that
    /// can't be reached is a failed sign-in, reported as such.
    @MainActor
    private func signIn(_ acct: Account, _ provider: AuthService.Provider, identityToken: String?) async throws {
        guard defaults != nil else {
            persist(acct)
            return
        }
        guard let identityToken else { throw SignInError.unexpectedCredential }
        let revision = Self.identityRevision
        let session = try await AuthService().exchange(identityToken, from: provider)
        // Signed out, or in as someone else, while the request was out.
        guard Self.identityRevision == revision else { throw CancellationError() }
        // The Worker's id and the app's must name the same person, or every
        // write would be refused as someone else's.
        guard OneDayAPI.authorID(forSessionUser: session.userId) == acct.id else {
            throw SignInError.unexpectedCredential
        }
        persist(acct)
        SessionKeychain.standard.save(session)
        hasSession = true
        SharedActivityNotificationService.reconcileSavedRooms()
    }

    /// Google can hand over a fresh token without asking, so a Google account
    /// whose session lapsed gets a new one on launch. Apple can't: that
    /// person sees the sign-in button again.
    private func restoreGoogleSession(for id: String) {
        guard defaults != nil, id.hasPrefix(Self.googlePrefix) else { return }
        Task { @MainActor in
            guard let user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn(),
                  let googleID = user.userID, Self.googlePrefix + googleID == id,
                  let account
            else { return }
            try? await signIn(account, .google, identityToken: user.idToken?.tokenString)
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

    /// Keeps the controller's delegate alive for the length of the request;
    /// `ASAuthorizationController` holds it weakly.
    private var existingAccountRelay: ExistingAccountRelay?

    /// Someone reinstalling, or on a new phone, has an Apple ID this app has
    /// already seen. Apple can offer it straight away — one tap and Face ID,
    /// instead of finding the button. If there's no such credential the
    /// request fails without showing anything, which is the whole point of
    /// `preferImmediatelyAvailableCredentials`.
    @MainActor
    func offerExistingAccount() {
        guard !isSignedIn, defaults != nil, existingAccountRelay == nil else { return }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        configure(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let relay = ExistingAccountRelay(controller: controller) { [weak self] result in
            guard let self else { return }
            self.existingAccountRelay = nil
            if case .success = result { Task { _ = try? await self.completeSignIn(result) } }
        }
        existingAccountRelay = relay
        controller.performRequests(options: .preferImmediatelyAvailableCredentials)
    }

    private func persist(_ account: Account) {
        if defaults != nil, self.account?.id != account.id {
            Self.identityRevision &+= 1
            // The last person's session must not outlive them.
            SessionKeychain.standard.delete()
            hasSession = false
        }
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

/// The delegate and presentation anchor for `offerExistingAccount`, kept out
/// of `AccountStore` so the store doesn't have to become an `NSObject`.
private final class ExistingAccountRelay: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private let controller: ASAuthorizationController
    private let completion: (Result<ASAuthorization, Error>) -> Void

    init(controller: ASAuthorizationController,
         completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.controller = controller
        self.completion = completion
        super.init()
        controller.delegate = self
        controller.presentationContextProvider = self
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        completion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
