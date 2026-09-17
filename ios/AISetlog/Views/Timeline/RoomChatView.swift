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

    /// The moment's own prompt, so a quote can say 「第 2 个瞬间 · 咖啡」 rather
    /// than just a number. Nil for a record-by-time story, which has no prompts.
    private func momentTitle(_ day: Int) -> String? {
        guard let challenge = store.challenge(challengeID), !challenge.isTimeOnly else {
            return nil
        }
        return ChallengePresenter(challenge: challenge).title(forSlot: day)
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
                    momentTitle: momentTitle,
                    onOpenMoment: onOpenMoment)
                    .id("\(sessionSource.identity):\(me.id):\(code)")
            }
        } else {
            VStack(spacing: 20) {
                Text(language.resolved == .chinese ? "登录并加入房间后才能聊天。" : "Sign in and join the room to chat.")
                Button(Strings.done) { dismiss() }
            }.padding()
        }
    }
}

#if DEBUG || LOCAL_ROOM_CHAT_DEMO
@MainActor
struct RoomChatDemoView: View {
    let chinese: Bool

    var body: some View {
        LocalRoomDemoView(chinese: chinese)
    }
}
#endif

private struct RoomChatConversation: View {
    @StateObject private var session: RoomChatSession
    private let authorName: String
    private let preview: RoomChatDemoTransport?
    @State private var showDemo = false
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
        momentTitle: @escaping (Int) -> String?,
        onOpenMoment: ((Int) -> Void)?
    ) {
        self.authorName = authorName
        self.preview = source.preview
        self.momentTitle = momentTitle
        self.onOpenMoment = onOpenMoment
        _moment = State(initialValue: moment)
        _session = StateObject(wrappedValue: source.makeSession(scope: scope))
    }

    /// 「第 2 个瞬间 · 咖啡」, or just the number for a story without prompts.
    private func momentLabel(_ day: Int) -> String {
        let numbered = text("第 \(day) 个瞬间", "Moment \(day)")
        guard let title = momentTitle(day), !title.isEmpty else { return numbered }
        return "\(numbered) · \(MomentCatalog.localize(title))"
    }

    private func text(_ zh: String, _ en: String) -> String { language.resolved == .chinese ? zh : en }
    private var entries: [RoomChatEntry] { session.state?.orderedEntries ?? [] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if preview != nil {
                    Text(text("本地演示 · 不会发送给朋友", "Local demo · Nothing is sent to friends"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.oneDayLavender.opacity(0.14))
                }
                if let error = session.error {
                    HStack {
                        Text(errorText(error))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(OneDay.ink)
                        if error == .fetch {
                            Button(text("重试", "Retry")) { Task { await session.refresh() } }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.oneDayBrand)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.oneDayAmber.opacity(0.16))
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if entries.isEmpty {
                                Text(text("在这里聊聊你们的故事", "Talk about your story here"))
                                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(OneDay.inkSoft)
                                    .padding(.top, 48)
                            }
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                bubble(entry, namesAuthor: namesAuthor(at: index)).id(entry.id)
                            }
                            Color.clear.frame(height: 1).id("latest")
                                .onAppear { followsLatest = true }
                                .onDisappear { followsLatest = false }
                        }.padding()
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: entries.count) { _, _ in
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
            .navigationTitle(preview == nil ? text("房间聊天", "Room chat") : text("聊天演示", "Chat demo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG || LOCAL_ROOM_CHAT_DEMO
                if preview == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(text("演示", "Demo")) { showDemo = true }
                    }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button(preview == nil ? Strings.done : text("退出演示", "Exit demo")) { dismiss() }
                }
            }
            .sheet(isPresented: $showDemo) {
                #if DEBUG || LOCAL_ROOM_CHAT_DEMO
                RoomChatDemoView(chinese: language.resolved == .chinese)
                #endif
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .confirmationDialog(text("删除这条消息？", "Delete this message?"), isPresented: Binding(
                get: { deletionCandidate != nil }, set: { if !$0 { deletionCandidate = nil } })) {
                Button(text("删除消息", "Delete message"), role: .destructive) {
                    if let id = deletionCandidate { Task { await session.delete(id) } }
                    deletionCandidate = nil
                }
            } message: {
                Text(text("删除成功后，房间里的其他人刷新时也会移除这条消息。", "Once deleted, this message will be removed for others when they refresh."))
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

    private func bubble(_ entry: RoomChatEntry, namesAuthor: Bool) -> some View {
        let mine = isMine(entry)
        return HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                if namesAuthor {
                    Text(entry.message.authorName)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
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
                .foregroundStyle(mine ? Color.white : OneDay.ink)
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
                        Button(text("删除消息", "Delete message"), role: .destructive) {
                            deletionCandidate = entry.id
                        }.disabled(session.deletingIDs.contains(entry.id))
                    }
                }
                HStack(spacing: 8) {
                    Text(entry.message.createdAt, format: .dateTime.month().day().hour().minute())
                    if mine {
                        switch entry.delivery {
                        case .sending: Text(text("发送中", "Sending"))
                        case .sent:
                            Text(session.deletingIDs.contains(entry.id) ? text("正在删除", "Deleting") : text("已发送", "Sent"))
                        case .failed:
                            Button(text("发送失败 · 重试", "Failed · Retry")) {
                                Task { await session.retry(entry.id) }
                            }.padding(.vertical, 8)
                        }
                    }
                }
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.inkFaint)
            }
            if !mine { Spacer(minLength: 40) }
        }
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
            Text(momentLabel(day))
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
                    Text(text("在说：\(momentLabel(context))", "About: \(momentLabel(context))"))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayNavy)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        moment = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(OneDay.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text("取消引用", "Remove context"))
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
                TextField(text("发消息…", "Message…"), text: Binding(
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
                Button {
                    followsLatest = true
                    Task { await session.send(authorName: authorName, moment: moment) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(OneDay.brandHorizontal, in: Circle())
                        .oneDayGlow(.oneDayBrand, strength: 0.8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(text("发送", "Send"))
                .disabled(session.state?.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false ||
                          (session.state?.draft.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > RoomChatState.maximumMessageLength)
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

    private func errorText(_ error: RoomChatSession.Failure) -> String {
        switch error {
        case .storage: text("无法保存聊天数据，请勿清除应用数据。", "Could not save chat data. Do not clear app data.")
        case .fetch: text("暂时无法获取新消息，已保留现有消息。", "Could not fetch new messages. Existing messages are kept.")
        case .send: text("有消息未发送成功，请点消息下方重试。", "A message failed to send. Tap Retry below it.")
        case .delete: text("删除失败，消息已保留。长按消息可再次删除。", "Deletion failed. The message is kept. Long press it to try again.")
        case .messageTooLong: text("每条消息最多 2000 个字符，文字已保留。", "Messages can have up to 2,000 characters. Your text is kept.")
        }
    }
}
