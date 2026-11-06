import SwiftUI
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift

/// Gate shown before a user can create or join a shared room. Local-only
/// challenges skip this entirely.
struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    /// Called once sign-in succeeds so the caller can continue its flow.
    var onSignedIn: () -> Void

    @State private var errorMessage: String?

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.oneDayBrand.gradient)

            VStack(spacing: 8) {
                Text(Strings.recordTogether)
                    .font(.title2.bold())
                Text(Strings.signInBody)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    // Without this the medium detent squeezes two lines into
                    // one and truncates: the sheet asks for an Apple ID and
                    // cuts off the sentence explaining what it's for.
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            AppleSignInButton(height: 50) {
                onSignedIn()
                dismiss()
            } onError: { errorMessage = $0 }

            GoogleAccountButton {
                onSignedIn()
                dismiss()
            } onError: { errorMessage = $0 }

            #if DEBUG
            // Two simulators can't both get through Sign in with Apple, so a
            // debug build can join a room as a throwaway identity instead.
            Button("Use a test identity (debug)") {
                account.signInAsTester()
                onSignedIn()
                dismiss()
            }
            .font(.footnote.weight(.semibold))
            #endif

            Button(Strings.notNow) { dismiss() }
                .font(.subheadline)
                .padding(.bottom, 8)
        }
        .padding(24)
    }
}

/// Sign in with Apple, finished in place: the gate sheet above and the
/// signed-out card in settings both use it, so tapping it never opens a
/// second screen with the same button on it.
struct AppleSignInButton: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat = 50
    var onSignedIn: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            account.configure(request)
        } onCompletion: { result in
            Task { @MainActor in
                do {
                    try await account.completeSignIn(result)
                    onSignedIn()
                } catch {
                    if (error as? ASAuthorizationError)?.code == .canceled || error is CancellationError { return }
                    onError(Strings.signInFailure(error))
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: height)
    }
}

/// Google's own button, so the logo and wording follow Google's branding
/// rules; its label follows the phone's language, not the in-app one.
struct GoogleAccountButton: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    var onSignedIn: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    var body: some View {
        GoogleSignInButton(scheme: colorScheme == .dark ? .dark : .light, style: .wide) {
            Task { @MainActor in
                do {
                    try await account.signInWithGoogle()
                    onSignedIn()
                } catch {
                    if (error as? GIDSignInError)?.code == .canceled || error is CancellationError { return }
                    onError(Strings.signInFailure(error))
                }
            }
        }
        .accessibilityIdentifier("google-sign-in")
    }
}
