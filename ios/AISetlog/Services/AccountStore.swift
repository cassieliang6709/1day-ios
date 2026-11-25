import Foundation
import AuthenticationServices
import GoogleSignIn
import UIKit
import Observation

@Observable
final class AccountStore {
    struct Account: Codable {
        let id: String
        var displayName: String

        var name: String? { displayName.isEmpty ? nil : displayName }
    }

    private static let key = "account.v1"

    private static let manufacturedNames: Set<String> = ["朋友", "Friend"]

    private static func sanitized(_ account: Account) -> Account {
        guard manufacturedNames.contains(account.displayName) else { return account }
        var fixed = account
        fixed.displayName = ""
        return fixed
    }
    private(set) static var identityRevision: UInt64 = 0

    static var persistedUserID: String? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let account = try? JSONDecoder().decode(Account.self, from: data)
        else { return nil }
        return account.id
    }

    private(set) var account: Account?
    private(set) var hasSession: Bool
    var isSignedIn: Bool {
        guard let account else { return false }
        #if DEBUG
        if account.id.hasPrefix(Self.testerPrefix) { return true }
        #endif
        return hasSession
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasSession = SessionKeychain.standard.load().map { $0.expiresAt > .now } ?? false
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Account.self, from: data) {
            let repaired = Self.sanitized(saved)
            account = repaired
            if repaired.displayName != saved.displayName { persist(repaired) }
            revalidate(saved.id)
            if !hasSession { restoreGoogleSession(for: saved.id) }
        }
        #if DEBUG
        if account == nil, let tester = defaults.string(forKey: "debugTester"), !tester.isEmpty {
            signInAsTester(named: tester)
        }
        #endif
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

    private func revalidate(_ userID: String) {
        #if DEBUG
        if userID.hasPrefix(Self.testerPrefix) { return }
        #endif
        if userID.hasPrefix(Self.googlePrefix) { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            guard Self.signsOut(on: state) else { return }
            Task { @MainActor in self?.signOut() }
        }
    }

    static func signsOut(on state: ASAuthorizationAppleIDProvider.CredentialState) -> Bool {
        state == .revoked
    }

    func signOut() {
        if defaults != nil {
            Self.identityRevision &+= 1
            SharedActivityNotificationService.removeSubscriptions(session: SessionKeychain.standard.load())
            SessionKeychain.standard.delete()
            GIDSignIn.sharedInstance.signOut()
        }
        hasSession = false
        account = nil
        defaults?.removeObject(forKey: Self.key)
    }


    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    @discardableResult
    func completeSignIn(_ result: Result<ASAuthorization, Error>) async throws -> Account {
        switch result {
        case .failure(let error):
            throw error
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw SignInError.unexpectedCredential
            }
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


    static let googlePrefix = "google:"

    @MainActor
    func signInWithGoogle() async throws {
        guard let presenter = Self.topViewController() else { throw SignInError.unexpectedCredential }
        let user = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter).user
        guard let googleID = user.userID else { throw SignInError.unexpectedCredential }
        let id = Self.googlePrefix + googleID
        let kept = account?.id == id ? account?.name : nil
        let name = kept ?? Self.normalized(user.profile?.name ?? "") ?? ""
        try await signIn(
            Account(id: id, displayName: name), .google, identityToken: user.idToken?.tokenString)
    }

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


    @MainActor
    private func signIn(_ acct: Account, _ provider: AuthService.Provider, identityToken: String?) async throws {
        guard defaults != nil else {
            persist(acct)
            return
        }
        guard let identityToken else { throw SignInError.unexpectedCredential }
        let revision = Self.identityRevision
        let session = try await AuthService().exchange(identityToken, from: provider)
        guard Self.identityRevision == revision else { throw CancellationError() }
        guard OneDayAPI.authorID(forSessionUser: session.userId) == acct.id else {
            throw SignInError.unexpectedCredential
        }
        persist(acct)
        SessionKeychain.standard.save(session)
        hasSession = true
        SharedActivityNotificationService.reconcileSavedRooms()
    }

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

    static let nameLimit = 24

    func rename(to newName: String) {
        guard var updated = account, let name = Self.normalized(newName) else { return }
        updated.displayName = name
        persist(updated)
    }

    static func normalized(_ raw: String) -> String? {
        let trimmed = String(
            raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
        return trimmed.isEmpty ? nil : trimmed
    }

#if DEBUG
    static let testerPrefix = "tester-"

    func signInAsTester(named name: String? = nil) {
        persist(Account(
            id: Self.testerPrefix + UUID().uuidString,
            displayName: name ?? UIDevice.current.name))
    }
#endif

    private var existingAccountRelay: ExistingAccountRelay?

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
