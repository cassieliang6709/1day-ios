import SwiftUI

/// All entry points resolve the current account and the same room, never the
/// currently selected clip author. Recreate the session when the account changes.
struct RoomChatView: View {
    let challengeID: UUID
    var moment: Int? = nil
    /// What to do when somebody taps a message's "about moment N" quote.
    ///
    /// Nil means the quote is text rather than a link — which is what it was
    /// everywhere until now: `RoomChatMessage.moment` was written on send and
    /// then printed as a grey caption nobody could act on. The host has to
    /// supply this because only the host knows how to get to a moment from
    /// where it put the chat.
    var onOpenMoment: ((Int) -> Void)?
    /// Whose clip, on which day, the reaction row at the top belongs to.
    ///
    /// Reactions used to be a row of their own on the review screen, under the
    /// picture — a floating strip of emoji that was the first thing you saw
    /// after your own face. They belong with the other thing people say about
    /// a moment, which is the thread. Nil when the chat was opened from the
    /// story rather than from one clip: there is no single take to react to.
    var reactionTarget: ReactionTarget?

    struct ReactionTarget: Equatable {
        let day: Int
        let authorID: String
    }

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.roomChatSessionSource) private var sessionSource
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    /// The moment's own name, so a quote can say 「咖啡」. Nil when it has
    /// none — a record-by-time story, or a room whose moments were never
    /// named. Chat only exists in a room, and a room doesn't number its days
    /// or moments on screen any more (1.5), so there is no 「第 2 个瞬间」 to
    /// fall back to.
    private func momentTitle(_ day: Int) -> String? {
        guard let challenge = store.challenge(challengeID) else { return nil }
        return ChallengePresenter(challenge: challenge).momentName(forSlot: day)
    }

    /// The moment's reactions, above the thread.
    @ViewBuilder
    private func reactionRow(_ target: ReactionTarget, myID: String) -> some View {
        let interactions = store.interactions(
            for: challengeID, day: target.day, targetAuthorID: target.authorID)
        ReactionBar(reactions: interactions.reactions, myID: myID) { emoji in
            store.toggleReaction(
                emoji, day: target.day, challengeID: challengeID,
                targetAuthorID: target.authorID)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    var body: some View {
        if let code = store.challenge(challengeID)?.roomCode, let me = account.account {
            VStack(spacing: 0) {
                if let target = reactionTarget {
                    reactionRow(target, myID: me.id)
                }
                RoomChatConversation(
                    scope: .init(accountID: me.id, roomCode: code),
                    authorName: me.displayName,
                    moment: moment,
                    source: sessionSource,
                    clips: RoomChatTimeline.clipEvents(
                        from: store.recordedClips(for: challengeID),
                        myID: me.id,
                        momentTitle: momentTitle),
                    momentTitle: momentTitle,
                    onOpenMoment: onOpenMoment)
                    .id("\(sessionSource.identity):\(me.id):\(code)")
            }
        } else {
            VStack(spacing: 20) {
                Text(Strings.chatSignInToJoin)
                Button(Strings.done) { dismiss() }
            }.padding()
        }
    }
}

private struct RoomChatConversation: View {
    @StateObject private var session: RoomChatSession
    private let authorName: String
    private let preview: RoomChatDemoTransport?
    /// The room's clips, threaded between the messages by time.
    private let clips: [RoomChatClipEvent]
    /// A clip being watched from here, when the host gave no way to open its
    /// moment (the chat opened from a clip's own player).
    @State private var playing: RoomChatClipEvent?
    @State private var moment: Int?
    @State private var followsLatest = true
    @State private var deletionCandidate: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    private let momentTitle: (Int) -> String?
    private let onOpenMoment: ((Int) -> Void)?

    init(
        scope: RoomChatScope,
        authorName: String,
        moment: Int?,
        source: RoomChatSessionSource,
        clips: [RoomChatClipEvent] = [],
        momentTitle: @escaping (Int) -> String?,
        onOpenMoment: ((Int) -> Void)?
    ) {
        self.authorName = authorName
        self.preview = source.preview
        self.clips = clips
        self.momentTitle = momentTitle
        self.onOpenMoment = onOpenMoment
        _moment = State(initialValue: moment)
        _session = StateObject(wrappedValue: source.makeSession(scope: scope))
    }

    /// The composer's band and the quote inside a bubble both say the
    /// moment's own name — 「咖啡」. They used to lead with 「第 2 个瞬间」,
    /// and the quote fell back to it when there was no name; a room doesn't
    /// number its moments on screen any more (1.5), so without a name it is
    /// just 「这个瞬间」.
    private func momentLabel(_ day: Int) -> String {
        guard let title = momentTitle(day), !title.isEmpty else { return Strings.thisMoment }
        return MomentCatalog.localize(title)
    }

    private func quoteLabel(_ day: Int) -> String { momentLabel(day) }

    private var entries: [RoomChatEntry] { session.state?.orderedEntries ?? [] }

    /// What the thread shows: the messages, with the room's clips threaded in
    /// by when they were filmed. See `RoomChatTimeline`.
    private var items: [RoomChatItem] { RoomChatTimeline.merge(entries: entries, clips: clips) }

    private var myAccountID: String { session.state?.scope.accountID ?? "" }

    /// My newest message — the only one whose "sending…" is worth a line.
    /// Every bubble used to end in 已发送 or 发送中, which in a normal thread
    /// is the same word under every message I wrote.
    private var myLatestID: UUID? { entries.last(where: isMine)?.id }

    /// Whether to print the time above this row: the first one, and any that
    /// comes after five minutes of quiet. A timestamp under every bubble was
    /// the loudest thing in the thread and said the same minute ten times.
    private func startsNewTimeBlock(at index: Int, in items: [RoomChatItem]) -> Bool {
        guard index > 0 else { return true }
        return items[index].date.timeIntervalSince(items[index - 1].date) > 5 * 60
    }

    /// The first of a run of rows from one other person — where their face
    /// goes. Later bubbles in the run leave the space empty so the run still
    /// lines up.
    private func startsRun(at index: Int, in items: [RoomChatItem]) -> Bool {
        guard index > 0, !startsNewTimeBlock(at: index, in: items) else { return true }
        return items[index - 1].authorKey(myID: myAccountID)
            != items[index].authorKey(myID: myAccountID)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if preview != nil {
                    Text(Strings.chatLocalDemoBanner)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.oneDayLavender.opacity(0.14))
                        .accessibilityIdentifier("chat-local-demo-banner")
                }
                if let error = session.error {
                    HStack {
                        Text(errorText(error))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(OneDay.ink)
                        if error == .fetch {
                            Button(Strings.retry) { Task { await session.refresh() } }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(OneDay.brandText)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.oneDayAmber.opacity(0.16))
                }
                ScrollViewReader { proxy in
                    let rows = items
                    let entryIndex = Dictionary(
                        uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) })
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if rows.isEmpty {
                                Text(Strings.chatEmpty)
                                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(OneDay.inkSoft)
                                    .padding(.top, 48)
                            }
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                                VStack(spacing: 10) {
                                    if startsNewTimeBlock(at: index, in: rows) {
                                        timeSeparator(item.date)
                                    }
                                    switch item {
                                    case .message(let entry):
                                        bubble(
                                            entry,
                                            namesAuthor: entryIndex[entry.id].map { namesAuthor(at: $0) } ?? false,
                                            startsRun: startsRun(at: index, in: rows))
                                    case .clip(let event):
                                        clipRow(event)
                                    }
                                }
                                .id(item.id)
                            }
                            Color.clear.frame(height: 1).id("latest")
                                .onAppear { followsLatest = true }
                                .onDisappear { followsLatest = false }
                        }.padding()
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: items.count) { _, _ in
                        if followsLatest { proxy.scrollTo("latest", anchor: .bottom) }
                    }
                }
            }
            // The app's own canvas. This screen was the only one still on
            // `systemGroupedBackground` with `secondarySystemGroupedBackground`
            // bubbles and a `systemGray6` field — system greys on a system
            // grey, which is why the one input on the page was the hardest
            // thing on it to find.
            .background(OneDayCanvas(seed: 4))
            // No 演示 button and no 聊天演示 title any more. The demo was a
            // second, local sample room opened from inside a real room's chat
            // — in a Debug build that is every build the owner runs, so it sat
            // in the top-left of every real conversation. The local sample
            // still exists (home screen, behind `-demoEntries`), and inside it
            // this screen is the real one with a banner, not a different mode.
            .navigationTitle(Strings.chatTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                        .accessibilityIdentifier("chat-done")
                }
            }
            .fullScreenCover(item: $playing) { event in
                clipPlayer(event)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .confirmationDialog(Strings.chatDeleteTitle, isPresented: Binding(
                get: { deletionCandidate != nil }, set: { if !$0 { deletionCandidate = nil } })) {
                Button(Strings.chatDeleteMessage, role: .destructive) {
                    if let id = deletionCandidate { Task { await session.delete(id) } }
                    deletionCandidate = nil
                }
            } message: {
                Text(Strings.chatDeleteForEveryone)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await session.refresh()
                do { try await Task.sleep(for: .seconds(10)) }
                catch { return }
            }
        }
    }

    private func isMine(_ entry: RoomChatEntry) -> Bool {
        entry.message.authorID == session.state?.scope.accountID
    }

    /// Whether this bubble has to say whose it is.
    ///
    /// The name used to sit over every bubble, so the room most people are in
    /// — two of you — printed the same two names six times down one screen,
    /// including over my own messages, which are already the blue ones on the
    /// right. A name answers "which of you said this", and in a two-person
    /// room there is only one other answer: it gets said once, on the first
    /// thing the other person says, and after that the side of the screen the
    /// bubble is on carries it. Three or more people in the room and the
    /// question comes back, so each run of messages is labelled again.
    private func namesAuthor(at index: Int) -> Bool {
        let entry = entries[index]
        guard !isMine(entry) else { return false }
        let earlier = entries[..<index]
        guard earlier.contains(where: { !isMine($0) }) else { return true }
        let others = Set(entries.filter { !isMine($0) }.map(\.message.authorID))
        guard others.count > 1 else { return false }
        return earlier.last?.message.authorID != entry.message.authorID
    }

    /// The time a block of messages starts, centred over it.
    private func timeSeparator(_ date: Date) -> some View {
        Text(date, format: .dateTime.month().day().hour().minute())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(OneDay.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private static let avatarSize: CGFloat = 26

    /// One message. Somebody else's carries their face beside the first
    /// bubble of each run and, where a name is needed at all, the name in
    /// their own colour — the same `Identity` tint as their avatar and their
    /// clips' bylines, so a person reads as one colour across the app. The
    /// grey name this replaces looked the same for everyone in the room.
    private func bubble(_ entry: RoomChatEntry, namesAuthor: Bool, startsRun: Bool) -> some View {
        let mine = isMine(entry)
        return HStack(alignment: .top, spacing: 8) {
            if mine {
                Spacer(minLength: 40)
            } else {
                Group {
                    if startsRun {
                        AvatarDot(name: entry.message.authorName, size: Self.avatarSize)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                // The name is said by the bubble's label below.
                .accessibilityHidden(true)
                // Level with the bubble rather than the name above it.
                .padding(.top, namesAuthor ? 19 : 0)
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                if namesAuthor {
                    Text(entry.message.authorName)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Identity.tint(for: entry.message.authorName))
                }
                VStack(alignment: .leading, spacing: 7) {
                    if let context = entry.message.moment {
                        quote(context, mine: mine)
                    }
                    Text(entry.message.text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .textSelection(.enabled)
                }
                // The tail corner is the one nearest its owner, so a run of
                // messages reads as coming from one side.
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .foregroundStyle(mine ? OneDay.onBrand : OneDay.ink)
                .background {
                    let shape = UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 17,
                            bottomLeading: mine ? 17 : 5,
                            bottomTrailing: mine ? 5 : 17,
                            topTrailing: 17),
                        style: .continuous)
                    if mine {
                        shape.fill(OneDay.brandHorizontal)
                    } else {
                        shape.fill(OneDay.surface)
                            .overlay { shape.strokeBorder(OneDay.hairline, lineWidth: 1) }
                    }
                }
                .oneDaySoftShadow(strength: mine ? 0 : 0.5)
                .contextMenu {
                    if mine && entry.delivery == .sent {
                        Button(Strings.chatDeleteMessage, role: .destructive) {
                            deletionCandidate = entry.id
                        }.disabled(session.deletingIDs.contains(entry.id))
                    }
                }
                if mine { deliveryLine(entry) }
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    private static let clipThumbSize = CGSize(width: 116, height: 154)

    /// A clip in the thread: who filmed it (and the moment, when it has a
    /// name) over a still of it with the time it was filmed. Mine on the
    /// right and others on the left, like a message — it is the room's other
    /// way of saying something. Every clip row carries its author's face,
    /// because the line names them anyway and a clip is never a reply in a
    /// run of chatter.
    ///
    /// Tapping plays it through the host's moment player when the chat was
    /// opened from the room page (`onOpenMoment`), which is the same path a
    /// tile on that page takes; opened from a clip's own player there is no
    /// page to go back to, so it plays here.
    private func clipRow(_ event: RoomChatClipEvent) -> some View {
        let mine = event.isMine
        return HStack(alignment: .top, spacing: 8) {
            if mine {
                Spacer(minLength: 40)
            } else {
                AvatarDot(name: event.authorName, size: Self.avatarSize)
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    .accessibilityHidden(true)
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                Text(Strings.chatClipEvent(name: event.authorName, moment: event.momentTitle))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(mine ? OneDay.inkSoft : Identity.tint(for: event.authorName))
                    .lineLimit(2)
                    .multilineTextAlignment(mine ? .trailing : .leading)
                Button {
                    if let onOpenMoment { onOpenMoment(event.day) } else { playing = event }
                } label: {
                    ClipThumbnail(url: event.url, refreshToken: event.recordedAt)
                        .frame(width: Self.clipThumbSize.width, height: Self.clipThumbSize.height)
                        .overlay {
                            LinearGradient(
                                colors: [.clear, .clear, .black.opacity(0.5)],
                                startPoint: .top, endPoint: .bottom)
                        }
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        }
                        .overlay(alignment: .bottomLeading) {
                            Text(event.recordedAt.formatted(.roomClock))
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                                .padding(9)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(OneDay.hairline, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(Strings.chatClipEvent(name: event.authorName, moment: event.momentTitle)), "
                        + event.recordedAt.formatted(date: .omitted, time: .shortened))
                .accessibilityIdentifier("chat-clip")
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    /// The clip on its own, full screen, with sound — the same looping player
    /// the room page's tiles use.
    private func clipPlayer(_ event: RoomChatClipEvent) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            LoopingClipPlayer(url: event.url, refreshToken: event.recordedAt)
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { playing = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(Strings.done)
            .padding(16)
        }
    }

    /// Only what needs saying. "Sending" under my newest message while it is
    /// on its way; "failed · retry" under *any* message that didn't go — that
    /// one stays wherever it is, because it is the only way to resend it; and
    /// "deleting" while a delete is in flight. A delivered message says
    /// nothing: delivered is the normal case.
    @ViewBuilder
    private func deliveryLine(_ entry: RoomChatEntry) -> some View {
        Group {
            if session.deletingIDs.contains(entry.id) {
                Text(Strings.chatDeleting)
            } else {
                switch entry.delivery {
                case .sending where entry.id == myLatestID:
                    Text(Strings.chatSending)
                case .failed:
                    Button(Strings.chatFailedRetry) {
                        Task { await session.retry(entry.id) }
                    }
                    .frame(minHeight: 44)
                default:
                    EmptyView()
                }
            }
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(OneDay.inkFaint)
    }

    /// What this message is about, inside the bubble it belongs to.
    ///
    /// `RoomChatMessage.moment` has been written on every message sent from a
    /// moment since chat shipped, and printed above the bubble as a grey
    /// `caption2` line reading 「来自第 2 个瞬间」 — a number with no name, no
    /// visual tie to the bubble, and nothing to tap. As a rule inside the
    /// bubble with the moment's own prompt on it, it says which moment and
    /// gets you there.
    @ViewBuilder
    private func quote(_ day: Int, mine: Bool) -> some View {
        let rule = mine ? Color.white.opacity(0.55) : Color.oneDayLavender
        let ink = mine ? Color.white.opacity(0.9) : OneDay.inkSoft
        let label = HStack(spacing: 5) {
            Text(quoteLabel(day))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
            if onOpenMoment != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(ink)
            }
        }
        .padding(.leading, 7)
        .overlay(alignment: .leading) {
            Capsule().fill(rule).frame(width: 2.5)
        }

        if let onOpenMoment {
            Button { onOpenMoment(day) } label: { label }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat-moment-quote")
        } else {
            label
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            // What the next message will be tagged with. Worth a tinted band
            // rather than a grey caption: it changes what gets *stored* on the
            // message, and the only clue it was on used to be one line of
            // `caption` type above the field.
            if let context = moment {
                HStack(spacing: 6) {
                    Text(Strings.chatAbout(momentLabel(context)))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayNavy)
                        .lineLimit(1)
                        .accessibilityIdentifier("chat-moment-about")
                    Spacer(minLength: 4)
                    Button {
                        moment = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(OneDay.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(Strings.chatRemoveContext))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.oneDayLavender.opacity(0.16), in: RoundedRectangle(
                    cornerRadius: 11, style: .continuous))
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.oneDayLavender).frame(width: 2.5).padding(.vertical, 5)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(Strings.chatPlaceholder, text: Binding(
                    get: { session.state?.draft ?? "" }, set: { session.setDraft($0) }), axis: .vertical)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .tint(Color.oneDayBrand)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    // White with a brand-coloured edge and a faint glow. It is
                    // the only place on this screen you can type, so it is the
                    // one thing that should be impossible to miss.
                    .background(OneDay.surface, in: RoundedRectangle(
                        cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.oneDayBrand.opacity(0.3), lineWidth: 1.5)
                    }
                    .oneDayGlow(.oneDayBrand, strength: 0.45)
                    .disabled(session.state == nil)
                    .accessibilityIdentifier("chat-input")
                Button {
                    followsLatest = true
                    Task { await session.send(authorName: authorName, moment: moment) }
                } label: {
                    // Visibly off while there's nothing to send. It used to be
                    // the same glowing blue disc either way, so an empty
                    // field's send button looked tappable and did nothing.
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(canSend ? OneDay.onBrand : OneDay.inkFaint)
                        .frame(width: 44, height: 44)
                        .background {
                            if canSend {
                                Circle().fill(OneDay.brandHorizontal)
                            } else {
                                Circle().fill(OneDay.surfaceSoft)
                            }
                        }
                        .oneDayGlow(.oneDayBrand, strength: canSend ? 0.8 : 0)
                        .animation(.easeOut(duration: 0.15), value: canSend)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(Strings.chatSend))
                .accessibilityIdentifier("chat-send")
                .disabled(!canSend)
            }
            if let count = session.state?.draft.count, count > 1_800 {
                Text("\(count) / \(RoomChatState.maximumMessageLength)")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        count > RoomChatState.maximumMessageLength
                            ? Color.red : OneDay.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private var canSend: Bool {
        let trimmed = session.state?.draft.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty && trimmed.count <= RoomChatState.maximumMessageLength
    }

    private func errorText(_ error: RoomChatSession.Failure) -> String {
        switch error {
        case .storage: Strings.chatErrorStorage
        case .fetch: Strings.chatErrorFetch
        case .send: Strings.chatErrorSend
        case .delete: Strings.chatErrorDelete
        case .messageTooLong: Strings.chatErrorTooLong(RoomChatState.maximumMessageLength)
        }
    }
}
