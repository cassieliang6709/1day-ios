import SwiftUI

struct RoomChatView: View {
    let challengeID: UUID
    var moment: Int? = nil
    var onOpenMoment: ((Int) -> Void)?
    var reactionTarget: ReactionTarget?
    var draft = ""

    struct ReactionTarget: Equatable {
        let day: Int
        let authorID: String
    }

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.roomChatSessionSource) private var sessionSource
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    private func momentTitle(_ day: Int) -> String? {
        guard let challenge = store.challenge(challengeID) else { return nil }
        return ChallengePresenter(challenge: challenge).momentName(forSlot: day)
    }

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
                onOpenMoment: onOpenMoment,
                draft: draft,
                header: reactionTarget.map { AnyView(reactionRow($0, myID: me.id)) })
                .id("\(sessionSource.identity):\(me.id):\(code)")
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
    private let clips: [RoomChatClipEvent]
    @State private var playing: RoomChatClipEvent?
    @State private var moment: Int?
    @State private var followsLatest = true
    @State private var deletionCandidate: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    private let momentTitle: (Int) -> String?
    private let onOpenMoment: ((Int) -> Void)?
    private let header: AnyView?
    private let draft: String

    init(
        scope: RoomChatScope,
        authorName: String,
        moment: Int?,
        source: RoomChatSessionSource,
        clips: [RoomChatClipEvent] = [],
        momentTitle: @escaping (Int) -> String?,
        onOpenMoment: ((Int) -> Void)?,
        draft: String = "",
        header: AnyView? = nil
    ) {
        self.header = header
        self.draft = draft
        self.authorName = authorName
        self.preview = source.preview
        self.clips = clips
        self.momentTitle = momentTitle
        self.onOpenMoment = onOpenMoment
        _moment = State(initialValue: moment)
        _session = StateObject(wrappedValue: source.makeSession(scope: scope))
    }

    private func momentLabel(_ day: Int) -> String {
        guard let title = momentTitle(day), !title.isEmpty else { return Strings.thisMoment }
        return MomentCatalog.localize(title)
    }

    private func quoteLabel(_ day: Int) -> String { momentLabel(day) }

    private var entries: [RoomChatEntry] { session.state?.orderedEntries ?? [] }

    private var items: [RoomChatItem] { RoomChatTimeline.merge(entries: entries, clips: clips) }

    private var myAccountID: String { session.state?.scope.accountID ?? "" }

    private var myLatestID: UUID? { entries.last(where: isMine)?.id }

    private func startsNewTimeBlock(at index: Int, in items: [RoomChatItem]) -> Bool {
        guard index > 0 else { return true }
        return items[index].date.timeIntervalSince(items[index - 1].date) > 5 * 60
    }

    private func startsRun(at index: Int, in items: [RoomChatItem]) -> Bool {
        guard index > 0, !startsNewTimeBlock(at: index, in: items) else { return true }
        return items[index - 1].authorKey(myID: myAccountID)
            != items[index].authorKey(myID: myAccountID)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if preview != nil {
                    Text(Strings.chatLocalDemoBanner)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.oneDayLavender.opacity(0.14))
                        .accessibilityIdentifier("chat-local-demo-banner")
                }
                if let error = session.error, error != .send {
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
            .background(OneDayCanvas(seed: 4))
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
        .onReceive(NotificationCenter.default.publisher(for: .roomActivityArrived)) { note in
            guard note.userInfo?["roomCode"] as? String == session.state?.scope.roomCode else { return }
            Task { await session.refresh() }
        }
        .onAppear {
            if !draft.isEmpty, session.state?.draft.isEmpty == true { session.setDraft(draft) }
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

    private func namesAuthor(at index: Int) -> Bool {
        let entry = entries[index]
        guard !isMine(entry) else { return false }
        let earlier = entries[..<index]
        guard earlier.contains(where: { !isMine($0) }) else { return true }
        let others = Set(entries.filter { !isMine($0) }.map(\.message.authorID))
        guard others.count > 1 else { return false }
        return earlier.last?.message.authorID != entry.message.authorID
    }

    private func timeSeparator(_ date: Date) -> some View {
        Text(date, format: .dateTime.month().day().hour().minute())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(OneDay.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private static let avatarSize: CGFloat = 26

    private func bubble(_ entry: RoomChatEntry, namesAuthor: Bool, startsRun: Bool) -> some View {
        let mine = isMine(entry)
        return HStack(alignment: .top, spacing: 8) {
            if mine {
                Spacer(minLength: 40)
            } else {
                Group {
                    if startsRun {
                        MemberFace(id: entry.message.authorID, name: entry.message.authorName,
                                   size: Self.avatarSize, showsMood: false)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .accessibilityHidden(true)
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
                    ClipTile(url: event.url, refreshToken: event.recordedAt, scrim: true)
                        .frame(width: Self.clipThumbSize.width, height: Self.clipThumbSize.height)
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
                                .padding(OneDay.Space.s)
                        }
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
