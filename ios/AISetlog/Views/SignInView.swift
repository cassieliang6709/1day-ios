import SwiftUI
import AuthenticationServices

/// Gate shown before a user can create or join a shared room. Local-only
/// challenges skip this entirely.
struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    /// Called once sign-in succeeds so the caller can continue its flow.
    var onSignedIn: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.setlogBlue.gradient)

            VStack(spacing: 8) {
                Text("Record together")
                    .font(.title2.bold())
                Text("Sign in so friends can see who filmed each clip.\nWe only use your name.")
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
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)

            Button("Not now") { dismiss() }
                .font(.subheadline)
                .padding(.bottom, 8)
        }
        .padding(24)
    }
}
