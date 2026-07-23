import SwiftUI

private enum BoardTheme {
    static let primary = Color.setlogBlue
    static let accent = Color.setlogCyan
    static let deep = Color.setlogNavy
    static let tint = Color.setlogSky
    static let page = Color.setlogMist
    static let card = Color.white.opacity(0.92)
    static let cardStrong = Color.white
    static let stroke = Color.setlogBlue.opacity(0.12)
    static let primaryText = Color(red: 0.05, green: 0.12, blue: 0.20)
    static let secondaryText = Color(red: 0.42, green: 0.49, blue: 0.57)

    static let background = LinearGradient(
        colors: [
            Color.setlogMist,
            Color.white,
            Color(red: 0.88, green: 0.96, blue: 1.0),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let actionGradient = LinearGradient(
        colors: [primary, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct ChallengeBoardView: View {
    let challengeID: UUID

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: BoardSheet?
    @State private var showFinalReel = false

    private var challenge: Challenge? { store.challenge(challengeID) }

    enum BoardSheet: Identifiable {
        case record(day: Int)
        case preview(day: Int)

        var id: String {
            switch self {
            case .record(let day): "record-\(day)"
            case .preview(let day): "preview-\(day)"
            }
        }
    }

    var body: some View {
        Group {
            if let challenge {
                board(for: challenge)
            }
        }
        .navigationTitle(challenge?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .tint(BoardTheme.primary)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    #if DEBUG
                    Button("Fill with demo clips") {
                        store.fillWithDemoClips(challengeID: challengeID)
                    }
                    #endif
                    Button("Delete challenge", role: .destructive) {
                        store.delete(challengeID)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(item: $sheet) { presented in
            switch presented {
            case .record(let day):
                RecordClipView(
                    day: day,
                    slotTitle: challenge?.title(forSlot: day),
                    clipLength: challenge?.resolvedClipLength ?? .tiny
                ) { url, overlayText in
                    store.saveClip(
                        from: url,
                        day: day,
                        challengeID: challengeID,
                        overlayText: overlayText)
                }
            case .preview(let day):
                if let card = challenge?.cards.first(where: { $0.day == day }),
                   let url = store.clipURL(for: card, in: challengeID) {
                    ClipPreviewView(
                        day: day,
                        slotTitle: challenge?.title(forSlot: day),
                        authorName: account.account?.displayName,
                        overlayText: card.overlayText,
                        clipLength: challenge?.resolvedClipLength ?? .tiny,
                        url: url,
                        recordedAt: card.recordedAt
                    ) {
                        sheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            sheet = .record(day: day)
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showFinalReel) {
            if let challenge {
                FinalReelView(
                    challenge: challenge,
                    clips: store.recordedClips(for: challengeID))
            }
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoReel") {
                store.fillWithDemoClips(challengeID: challengeID)
                showFinalReel = true
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPreview") {
                store.fillWithDemoClips(challengeID: challengeID)
                sheet = .preview(day: 2)
            }
        }
        #endif
    }

    // MARK: - Board

    private func board(for challenge: Challenge) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                progressHeader(challenge)

                if challenge.isShared {
                    rosterHeader(challenge)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(challenge.cards) { card in
                        DayCardView(
                            card: card,
                            status: challenge.cardStatus(card),
                            title: challenge.title(forSlot: card.day),
                            unitName: challenge.unitName,
                            clipURL: store.clipURL(for: card, in: challengeID)
                        )
                        .onTapGesture { handleTap(card, challenge: challenge) }
                    }
                }

                // Show for a shared room as soon as anyone has contributed, so a
                // freshly-joined member can watch before recording their own.
                if challenge.recordedCount > 0 || !store.recordedClips(for: challengeID).isEmpty {
                    Button {
                        showFinalReel = true
                    } label: {
                        Label(
                            challenge.isComplete
                                ? (challenge.isOneDay ? "Create 1-day film" : "Create weekly film")
                                : "Preview film · \(challenge.recordedCount)/\(challenge.cards.count) \(challenge.unitNamePlural)",
                            systemImage: "film.stack.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BoardTheme.primary)
                    .controlSize(.large)
                    .shadow(color: BoardTheme.deep.opacity(0.28), radius: 12, y: 6)
                }
            }
            .padding()
        }
        .background(BoardBackground())
        .sensoryFeedback(.success, trigger: challenge.recordedCount)
        .refreshable {
            if challenge.isShared { await store.syncRoom(challengeID) }
        }
        .task(id: challengeID) {
            if challenge.isShared { await store.syncRoom(challengeID) }
        }
    }

    /// Member chips + a "share code" pill for a shared room.
    private func rosterHeader(_ challenge: Challenge) -> some View {
        let members = store.members(for: challengeID)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(members.count) in this room", systemImage: "person.2.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(BoardTheme.primaryText)
                Spacer()
                if store.syncing.contains(challenge.roomCode ?? "") {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BoardTheme.primary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(members, id: \.id) { member in
                        MemberChip(name: member.name)
                    }
                }
            }
            if let code = challenge.roomCode {
                ShareLink(item: shareText(code: code, challenge: challenge)) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(challenge.recordedCount > 0 ? "Send today's invite · code " : "Invite friends · code ")
                            + Text(code).font(.subheadline.bold().monospaced())
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(BoardTheme.primaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(BoardTheme.cardStrong, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(BoardTheme.stroke, lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(BoardTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(BoardTheme.stroke, lineWidth: 1)
        )
    }

    private func shareText(code: String, challenge: Challenge) -> String {
        if challenge.recordedCount > 0 {
            let first = challenge.title(forSlot: 1)
            return "I just captured \(first) for “\(challenge.title)” on 1Day. Join my challenge! Code: \(code)\naisetlog://join?code=\(code)"
        }
        return "Join my “\(challenge.title)” challenge on 1Day! Code: \(code)\naisetlog://join?code=\(code)"
    }

    private func progressHeader(_ challenge: Challenge) -> some View {
        HStack(spacing: 16) {
            ProgressRing(recorded: challenge.recordedCount, total: challenge.cards.count)

            VStack(alignment: .leading, spacing: 4) {
                Text(progressTitle(challenge))
                    .font(.headline)
                    .foregroundStyle(BoardTheme.primaryText)
                Text(challenge.recordedCount == 7
                    ? "All clips in - time to make the film."
                    : "\(challenge.recordedCount) of 7 \(challenge.resolvedClipLength.secondsLabel) \(challenge.unitNamePlural) recorded")
                    .font(.subheadline)
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            Spacer()
        }
        .padding(16)
        .background(BoardTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(BoardTheme.stroke, lineWidth: 1)
        )
        .shadow(color: BoardTheme.deep.opacity(0.18), radius: 16, y: 8)
    }

    private func progressTitle(_ challenge: Challenge) -> String {
        if challenge.isOneDay {
            return challenge.isComplete ? "1-day film complete" : "7 moments in 24 hours"
        }
        if challenge.isComplete { return "Week complete" }
        return challenge.currentDay > 7 ? "Week complete" : "Day \(challenge.currentDay) of 7"
    }

    private func handleTap(_ card: DayCard, challenge: Challenge) {
        switch challenge.cardStatus(card) {
        case .today, .missed:
            sheet = .record(day: card.day)
        case .done:
            sheet = .preview(day: card.day)
        case .locked:
            break
        }
    }
}

// MARK: - Progress ring

private struct BoardBackground: View {
    var body: some View {
        ZStack {
            BoardTheme.background.ignoresSafeArea()
            Circle()
                .fill(BoardTheme.accent.opacity(0.16))
                .frame(width: 260, height: 260)
                .offset(x: -190, y: -260)
            Circle()
                .fill(BoardTheme.tint.opacity(0.18))
                .frame(width: 300, height: 300)
                .offset(x: 180, y: 360)
            Circle()
                .fill(BoardTheme.primary.opacity(0.08))
                .frame(width: 220, height: 220)
                .offset(x: -150, y: 460)
        }
    }
}

struct ProgressRing: View {
    let recorded: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(BoardTheme.primary.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(recorded) / CGFloat(total))
                .stroke(
                    BoardTheme.actionGradient,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: recorded)
            Text("\(recorded)/\(total)")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(BoardTheme.primaryText)
        }
        .frame(width: 56, height: 56)
    }
}

// MARK: - Member chip

struct MemberChip: View {
    let name: String

    private var tint: Color { Identity.tint(for: name) }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(initials.isEmpty ? "?" : initials)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: Circle())
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
        }
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .padding(.leading, 4)
        .foregroundStyle(BoardTheme.primaryText)
        .background(BoardTheme.cardStrong, in: Capsule())
        .overlay(Capsule().strokeBorder(BoardTheme.stroke, lineWidth: 1))
    }
}

// MARK: - Day card

struct DayCardView: View {
    let card: DayCard
    let status: DayCard.Status
    let title: String
    let unitName: String
    let clipURL: URL?

    var body: some View {
        // Color.clear fixes the 0.7 cell box. Every piece of content is an
        // edge-pinned overlay — overlays never resize the base, so nothing can
        // push past the clip frame (the bug the VStack-fill version had).
        Color.clear
            .aspectRatio(0.7, contentMode: .fit)
            .overlay { background(for: status).clipped() }
            .overlay { centerContent(for: status) }
            .overlay(alignment: .topTrailing) {
                if status == .done {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 3)
                        .padding(8)
                }
            }
            .overlay(alignment: .bottom) {
                if status == .done {
                    HStack {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                if status == .today {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(BoardTheme.actionGradient, lineWidth: 2)
                } else if status != .done {
                    // Unrecorded slots read as an empty storyboard frame —
                    // a dashed sketch outline rather than a filled block.
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            BoardTheme.secondaryText.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .shadow(
                color: status == .today ? BoardTheme.tint.opacity(0.45) : BoardTheme.deep.opacity(0.14),
                radius: status == .today ? 8 : 4, y: 3
            )
            .animation(.spring(duration: 0.45), value: card.clipFileName)
    }

    @ViewBuilder
    private func background(for status: DayCard.Status) -> some View {
        switch status {
        case .done:
            if let clipURL {
                // A live loop instead of a static frame — the board reads as
                // "footage in hand" the moment a slot is filled.
                LoopingClipPlayer(url: clipURL)
            } else {
                Color(.systemGray5)
            }
        case .today:
            BoardTheme.card
        case .missed:
            BoardTheme.card
        case .locked:
            Color.setlogMist.opacity(0.5)
        }
    }

    /// Centered label for the non-recorded states (today / missed / locked).
    @ViewBuilder
    private func centerContent(for status: DayCard.Status) -> some View {
        switch status {
        case .done:
            EmptyView()
        case .today:
            VStack(spacing: 6) {
                Image(systemName: ChallengeTemplate.icon(forPrompt: title))
                    .font(.system(size: 32))
                    .symbolEffect(.pulse)
                    .foregroundStyle(BoardTheme.primary)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text("Record")
                    .font(.system(size: 10))
                    .opacity(0.85)
            }
            .foregroundStyle(BoardTheme.primaryText)
        case .missed:
            VStack(spacing: 5) {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 24))
                    .foregroundStyle(BoardTheme.primary)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text("Catch up")
                    .font(.system(size: 10))
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            .foregroundStyle(BoardTheme.primaryText)
        case .locked:
            VStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20))
                Text("\(unitName.capitalized) \(card.day)")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(BoardTheme.secondaryText.opacity(0.72))
        }
    }
}
