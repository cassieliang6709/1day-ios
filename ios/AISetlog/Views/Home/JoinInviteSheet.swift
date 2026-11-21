import SwiftUI
import UIKit

struct JoinInviteSheet: View {
    @Binding var code: String
    let onCancel: () -> Void
    let onJoin: () -> Void

    @FocusState private var codeFocused: Bool
    @State private var pasteFailed = false

    private var normalizedCode: String { InviteCode.normalize(code) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OneDay.surface,
                    OneDay.surfaceSoft.opacity(0.85),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 26)
                    .padding(.top, 22)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 24) {
                        if pasteFailed {
                            Text(Strings.noCodeOnClipboard)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(OneDay.inkSoft)
                                .transition(.opacity)
                                .accessibilityIdentifier("paste-failed")
                        }

                        header
                        codeEntry
                    }
                    .padding(.horizontal, 26)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.never)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: join) {
                    Text(Strings.joinRoomButton)
                }
                .buttonStyle(.primaryAction)
                .disabled(!isComplete)
                .padding(.horizontal, 26)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            code = normalizedCode
            codeFocused = true
        }
    }

    private var isComplete: Bool { normalizedCode.count == 6 }

    private func join() {
        guard isComplete else { return }
        onJoin()
    }

    private var topBar: some View {
        HStack {
            Button(Strings.cancel, action: onCancel)
                .font(.headline)
            Spacer()
            Capsule()
                .fill(.secondary.opacity(0.18))
                .frame(width: 42, height: 5)
                .accessibilityHidden(true)
            Spacer()
            Button(Strings.paste) {
                if let pasted = UIPasteboard.general.string,
                   let found = InviteCode.extract(from: pasted) {
                    code = found
                    pasteFailed = false
                } else {
                    pasteFailed = true
                }
            }
            .font(.headline)
        }
        .foregroundStyle(OneDay.brandText)
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(OneDay.surface.opacity(0.9))
                    .frame(width: 86, height: 70)
                    .shadow(color: Color.oneDayBrand.opacity(0.15), radius: 14, y: 8)

                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(OneDay.brandText)
            }
            .accessibilityHidden(true)

            Text(Strings.enterInviteCode)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .multilineTextAlignment(.center)
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 10) {
            ZStack {
                HStack(spacing: 7) {
                    ForEach(0..<6, id: \.self) { index in
                        CodeSlot(character: character(at: index), isActive: normalizedCode.count == index)
                    }
                }
                .accessibilityHidden(true)

                TextField("", text: $code)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($codeFocused)
                    .submitLabel(.join)
                    .onSubmit(join)
                    .opacity(0.01)
                    .frame(height: 52)
                    .accessibilityLabel(Strings.inviteCodeLabel)
                    .accessibilityValue(spokenCode)
                    .accessibilityHint(Strings.inviteCodeFormatHint)
                    .accessibilityIdentifier("invite-code-field")
                    .onChange(of: code) { _, newValue in
                        let cleaned = InviteCode.normalize(newValue)
                        if cleaned != newValue { code = cleaned }
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture { codeFocused = true }

            Label(Strings.inviteCodeFormatHint, systemImage: "doc.on.clipboard")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }

    private var spokenCode: String {
        normalizedCode.map(String.init).joined(separator: " ")
    }

    private func character(at index: Int) -> String? {
        let chars = Array(normalizedCode)
        guard chars.indices.contains(index) else { return nil }
        return String(chars[index])
    }
}

struct CodeSlot: View {
    let character: String?
    let isActive: Bool

    var body: some View {
        Text(character ?? "")
            .font(.system(size: 22, weight: .black, design: .rounded))
            .monospaced()
            .foregroundStyle(OneDay.ink)
            .frame(width: 44, height: 54)
            .background(OneDay.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isActive ? Color.oneDayBrand : Color.secondary.opacity(0.35),
                        lineWidth: isActive ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }
}
