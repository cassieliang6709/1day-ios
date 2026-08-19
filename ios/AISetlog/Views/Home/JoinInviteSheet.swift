import SwiftUI
import UIKit

/// The join-a-room sheet: six code slots over a hidden text field, with
/// paste-from-clipboard and a gradient join button that activates at 6 chars.
struct JoinInviteSheet: View {
    @Binding var code: String
    let onCancel: () -> Void
    let onJoin: () -> Void

    @FocusState private var codeFocused: Bool

    private var normalizedCode: String {
        String(code.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }

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

            VStack(spacing: 24) {
                HStack {
                    Button(Strings.cancel, action: onCancel)
                        .font(.headline)
                    Spacer()
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 42, height: 5)
                    Spacer()
                    Button(Strings.paste) {
                        if let pasted = UIPasteboard.general.string {
                            code = String(pasted.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        }
                    }
                    .font(.headline)
                }
                .foregroundStyle(Color.oneDayBlue)

                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(OneDay.surface.opacity(0.9))
                            .frame(width: 86, height: 70)
                            .shadow(color: .cyan.opacity(0.15), radius: 14, y: 8)

                        Image(systemName: "envelope.open.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.oneDayBlue,
                                        Color.oneDayCyan,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    Text(Strings.enterInviteCode)
                        .font(.system(size: 28, weight: .black, design: .rounded))

                    Text(Strings.inviteHint)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ZStack {
                    HStack(spacing: 7) {
                        ForEach(0..<6, id: \.self) { index in
                            CodeSlot(character: character(at: index), isActive: normalizedCode.count == index)
                        }
                    }

                    TextField("", text: $code)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($codeFocused)
                        .opacity(0.01)
                        .frame(height: 52)
                        .onChange(of: code) { _, newValue in
                            let cleaned = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                            if cleaned != newValue { code = cleaned }
                        }
                }
                .contentShape(Rectangle())
                .onTapGesture { codeFocused = true }

                Button(action: onJoin) {
                    Text(Strings.joinRoomButton)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: normalizedCode.count == 6
                                    ? [Color.oneDayBlue, Color.oneDayCyan]
                                    : [Color.gray.opacity(0.28), Color.gray.opacity(0.22)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(normalizedCode.count < 6)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
        }
        .onAppear {
            code = normalizedCode
            codeFocused = true
        }
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
                        isActive ? Color(red: 0.0, green: 0.62, blue: 0.95) : Color.secondary.opacity(0.35),
                        lineWidth: isActive ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }
}
