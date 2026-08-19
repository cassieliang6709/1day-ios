import SwiftUI
import AuthenticationServices

/// Gate shown before a user can create or join a shared room. Local-only
/// challenges skip this entirely.
struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// Called once sign-in succeeds so the caller can continue its flow.
    var onSignedIn: () -> Void

    @State private var errorMessage: String?

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.oneDayBlue.gradient)

            VStack(spacing: 8) {
                Text(Strings.recordTogether)
                    .font(.title2.bold())
                Text(Strings.signInBody)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(.signIn) { request in
                account.configure(request)
            } onCompletion: { result in
                do {
                    try account.completeSignIn(result)
                    onSignedIn()
                    dismiss()
                } catch {
                    if (error as? ASAuthorizationError)?.code == .canceled { return }
                    errorMessage = error.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)

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
