import SwiftUI
import UIKit

/// Sub-components of `HomeView`: logo, join-by-code sheet, breathing start
/// button, history film-strip card, and the active-challenge row.

struct OneDayLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.oneDayBlue, Color.oneDayCyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.oneDayBlue.opacity(0.22), radius: side * 0.08, y: side * 0.05)

                Text("1D")
                    .font(.system(size: side * 0.34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Circle()
                    .stroke(.white.opacity(0.82), lineWidth: max(side * 0.045, 2))
                    .frame(width: side * 0.68, height: side * 0.68)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(.white)
                            .frame(width: side * 0.13, height: side * 0.13)
                            .offset(x: side * 0.02, y: -side * 0.02)
                    }
            }
        }
    }
}

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
                    Color(red: 0.96, green: 0.99, blue: 1.0),
                    Color.oneDayMist,
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
                            .fill(.white.opacity(0.88))
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
            .foregroundStyle(Color(red: 0.06, green: 0.12, blue: 0.18))
            .frame(width: 44, height: 54)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isActive ? Color(red: 0.0, green: 0.62, blue: 0.95) : Color.black.opacity(0.06),
                        lineWidth: isActive ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }
}

/// The "Start today" button with a slow breathing glow, so the home screen's
/// single most important action has some life to it.
struct BreathingStartButton: View {
    let action: () -> Void
    @State private var breathe = false

    var body: some View {
        Button(action: action) {
            Text(Strings.startToday)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.oneDayBlue, Color.oneDayCyan],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .shadow(color: Color.oneDayBlue.opacity(breathe ? 0.45 : 0.16), radius: breathe ? 22 : 8, y: 6)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

/// A completed challenge's "history" card — the clip's first frame peeking
/// through behind a date stamp, like a film-strip frame instead of a plain row.
struct FilmStripCard: View {
    let challenge: Challenge
    let clipURL: URL?

    private var dateStamp: String {
        challenge.startDate.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let clipURL {
                ClipThumbnail(url: clipURL)
                    .scaledToFill()
            } else {
                Color(.systemGray5)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if challenge.isShared {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(10)
        }
        .frame(width: 130, height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            Text(dateStamp)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.35), in: Capsule())
                .rotationEffect(.degrees(-6))
                .padding(8)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

struct ChallengeRow: View {
    let challenge: Challenge
    var memberCount: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            ProgressRing(recorded: challenge.recordedCount, total: challenge.cards.count)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(challenge.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if challenge.isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.oneDayBlue)
                    }
                }
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var statusText: String {
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        let range = "\(challenge.startDate.formatted(fmt)) – \((Calendar.current.date(byAdding: .day, value: 6, to: challenge.startDate) ?? challenge.startDate).formatted(fmt))"
        if challenge.isOneDay {
            if challenge.isComplete {
                return Strings.completedOn(challenge.startDate.formatted(fmt))
            }
            return Strings.oneDayProgress(challenge.recordedCount, secondsLabel: challenge.resolvedClipLength.secondsLabel)
        }
        if challenge.isShared, memberCount > 1 {
            return Strings.friendsRange(memberCount, range)
        }
        if challenge.isComplete {
            return Strings.completedRange(range)
        }
        if challenge.currentDay > 7 {
            return Strings.endedRecorded(challenge.recordedCount)
        }
        return Strings.dayOfRange(challenge.currentDay, range)
    }
}
