import SwiftUI

extension Color {
    static let setlogBlue = Color(red: 0.0, green: 0.55, blue: 0.95)
    static let setlogCyan = Color(red: 0.0, green: 0.76, blue: 0.88)
    static let setlogSky = Color(red: 0.48, green: 0.86, blue: 1.0)
    static let setlogNavy = Color(red: 0.02, green: 0.28, blue: 0.74)
    static let setlogMist = Color(red: 0.89, green: 0.98, blue: 1.0)
}

/// Landing screen: all challenges (active + past), start a new one or join a
/// friend's room any time.
struct HomeView: View {
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Binding var pendingJoinCode: String?

    @State private var path: [UUID] = []
    @State private var showNewChallenge = false
    @State private var showJoin = false
    @State private var joinCode = ""
    @State private var joining = false
    @State private var errorText: String?

    /// When set, present sign-in and run this once the user finishes.
    @State private var afterSignIn: (() -> Void)?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.challenges.isEmpty {
                    emptyState
                } else {
                    challengeList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .toolbar {
                if !store.challenges.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showNewChallenge = true
                            } label: {
                                Label("Start today", systemImage: "plus")
                            }
                            Button {
                                joinCode = ""
                                showJoin = true
                            } label: {
                                Label("Enter invite code", systemImage: "envelope")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showNewChallenge) {
                NewChallengeView { id in path.append(id) }
            }
            .sheet(isPresented: $showJoin) { joinSheet }
            .sheet(isPresented: Binding(
                get: { afterSignIn != nil },
                set: { if !$0 { afterSignIn = nil } }
            )) {
                SignInView { afterSignIn?() }
                    .presentationDetents([.medium])
            }
            .alert("Couldn't join", isPresented: Binding(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .navigationDestination(for: UUID.self) { id in
                ChallengeBoardView(challengeID: id)
            }
        }
        .onChange(of: pendingJoinCode) { _, code in
            if let code { startJoin(code); pendingJoinCode = nil }
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoReel") {
                let demo = store.challenges.first { $0.title == "Demo Week" }
                    ?? store.create(title: "Demo Week")
                path = [demo.id]
            }
            if ProcessInfo.processInfo.arguments.contains("-demoBoard") {
                let demo = store.challenges.first { $0.title == "Demo Week" }
                    ?? store.create(title: "Demo Week")
                store.fillWithDemoClips(challengeID: demo.id)
                path = [demo.id]
            }
            if ProcessInfo.processInfo.arguments.contains("-newChallenge") {
                showNewChallenge = true
            }
        }
        #endif
    }

    // MARK: - Join flow

    private var joinSheet: some View {
        JoinInviteSheet(
            code: $joinCode,
            onCancel: { showJoin = false },
            onJoin: {
                showJoin = false
                startJoin(joinCode)
            }
        )
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.hidden)
    }

    private func startJoin(_ code: String) {
        let code = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard code.count >= 6 else { return }
        let run = {
            joining = true
            Task {
                defer { joining = false }
                do {
                    let challenge = try await store.joinRoom(code: code)
                    path = [challenge.id]
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
        if account.isSignedIn { run() } else { afterSignIn = run }
    }

    // MARK: - List

    private var inProgress: [Challenge] { store.challenges.filter { !$0.isComplete } }
    private var history: [Challenge] { store.challenges.filter { $0.isComplete } }

    private var challengeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                homeHero

                if !inProgress.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(inProgress) { challenge in
                            Button {
                                path.append(challenge.id)
                            } label: {
                                ChallengeRow(challenge: challenge, memberCount: store.members(for: challenge.id).count)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(challenge.isShared ? "Leave room" : "Delete challenge", role: .destructive) {
                                    store.delete(challenge.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HISTORY")
                            .font(.caption.bold())
                            .foregroundStyle(Color.setlogBlue.opacity(0.62))
                            .kerning(1.2)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(history) { challenge in
                                    Button {
                                        path.append(challenge.id)
                                    } label: {
                                        FilmStripCard(
                                            challenge: challenge,
                                            clipURL: firstClipURL(for: challenge))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(challenge.isShared ? "Leave room" : "Delete challenge", role: .destructive) {
                                            store.delete(challenge.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .overlay {
            if joining { ProgressView("Joining…").controlSize(.large) }
        }
    }

    private func firstClipURL(for challenge: Challenge) -> URL? {
        challenge.cards.first { $0.clipFileName != nil }
            .flatMap { store.clipURL(for: $0, in: challenge.id) }
    }

    private var homeHero: some View {
        VStack(spacing: 18) {
            OneDayLogoMark()
                .frame(width: 92, height: 92)

            VStack(spacing: 6) {
                Text("Today is \(Date.now.formatted(.dateTime.month(.abbreviated).day())).")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.setlogNavy)
                Text("Start a new film?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            BreathingStartButton { showNewChallenge = true }
        }
        .padding(.top, 24)
        .padding(.bottom, 14)
        .padding(.horizontal)
    }

    private var emptyState: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.setlogMist,
                    Color(red: 0.95, green: 0.99, blue: 1.0),
                    Color(red: 0.82, green: 0.94, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.setlogCyan.opacity(0.18))
                .frame(width: 260, height: 260)
                .offset(x: -180, y: -280)
            Circle()
                .fill(Color.setlogSky.opacity(0.18))
                .frame(width: 260, height: 260)
                .offset(x: -160, y: 360)
            Circle()
                .fill(Color.setlogBlue.opacity(0.13))
                .frame(width: 260, height: 260)
                .offset(x: 170, y: 330)

            VStack(spacing: 26) {
                Spacer(minLength: 24)

                OneDayLogoMark()
                    .frame(width: 170, height: 170)
                    .padding(.bottom, 10)

                VStack(spacing: 10) {
                    Text("1Day")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(Color.setlogBlue)
                    Text("7 moments. One tiny vlog.")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.25, green: 0.31, blue: 0.38))
                }
                .multilineTextAlignment(.center)

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        showNewChallenge = true
                    } label: {
                        Text("Start today")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color.setlogBlue,
                                        Color.setlogCyan,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)

                    Button("I have an invite code") {
                        joinCode = ""
                        showJoin = true
                    }
                    .font(.headline)
                    .foregroundStyle(Color.setlogBlue)
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 34)
        }
    }
}

struct OneDayLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.setlogBlue, Color.setlogCyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.setlogBlue.opacity(0.22), radius: side * 0.08, y: side * 0.05)

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

private struct JoinInviteSheet: View {
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
                    Color.setlogMist,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button("Cancel", action: onCancel)
                        .font(.headline)
                    Spacer()
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 42, height: 5)
                    Spacer()
                    Button("Paste") {
                        if let pasted = UIPasteboard.general.string {
                            code = String(pasted.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        }
                    }
                    .font(.headline)
                }
                .foregroundStyle(Color.setlogBlue)

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
                                        Color.setlogBlue,
                                        Color.setlogCyan,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    Text("Enter invite code")
                        .font(.system(size: 28, weight: .black, design: .rounded))

                    Text("Ask your friend for the 6-character code.")
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
                    Text("Join today's room")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: normalizedCode.count == 6
                                    ? [Color.setlogBlue, Color.setlogCyan]
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

private struct CodeSlot: View {
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
private struct BreathingStartButton: View {
    let action: () -> Void
    @State private var breathe = false

    var body: some View {
        Button(action: action) {
            Text("Start today")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.setlogBlue, Color.setlogCyan],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .shadow(color: Color.setlogBlue.opacity(breathe ? 0.45 : 0.16), radius: breathe ? 22 : 8, y: 6)
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
private struct FilmStripCard: View {
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
                            .foregroundStyle(Color.setlogBlue)
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
                return "Completed · \(challenge.startDate.formatted(fmt))"
            }
            return "\(challenge.recordedCount)/7 \(challenge.resolvedClipLength.secondsLabel) moments · 24-hour film"
        }
        if challenge.isShared, memberCount > 1 {
            return "\(memberCount) friends · \(range)"
        }
        if challenge.isComplete {
            return "Completed · \(range)"
        }
        if challenge.currentDay > 7 {
            return "Ended · \(challenge.recordedCount)/7 recorded"
        }
        return "Day \(challenge.currentDay) of 7 · \(range)"
    }
}
