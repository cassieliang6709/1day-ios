import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    var onSignedIn: () -> Void

    @State private var errorMessage: String?

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

            GoogleAccountButton(height: 50) {
                onSignedIn()
                dismiss()
            } onError: { errorMessage = $0 }

            #if DEBUG
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

extension View {
    func signInGate(
        _ pending: Binding<(() -> Void)?>, onCancel: (() -> Void)? = nil
    ) -> some View {
        modifier(SignInGate(pending: pending, onCancel: onCancel))
    }
}

private struct SignInGate: ViewModifier {
    @Binding var pending: (() -> Void)?
    var onCancel: (() -> Void)?
    @State private var next: (() -> Void)?

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            onDismiss: {
                let run = next
                next = nil
                if let run { run() } else { onCancel?() }
            }
        ) {
            SignInView { next = pending }
                .presentationDetents([.medium])
        }
    }
}

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

struct GoogleAccountButton: View {
    @Environment(AccountStore.self) private var account
    var height: CGFloat = 50
    var onSignedIn: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    var body: some View {
        Button {
            Task { @MainActor in
                do {
                    try await account.signInWithGoogle()
                    onSignedIn()
                } catch {
                    if (error as? GIDSignInError)?.code == .canceled || error is CancellationError { return }
                    onError(Strings.signInFailure(error))
                }
            }
        } label: {
            HStack(spacing: OneDay.Space.s) {
                Image("GoogleG")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(Strings.signInWithGoogle)
                    .font(.system(size: height * 0.38, weight: .medium))
                    .foregroundStyle(Color.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("google-sign-in")
    }
}
