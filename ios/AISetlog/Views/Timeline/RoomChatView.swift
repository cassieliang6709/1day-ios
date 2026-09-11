import SwiftUI

/// All entry points resolve the current account and the same room, never the
/// currently selected clip author. Recreate the session when the account changes.
struct RoomChatView: View {
    let challengeID: UUID
    var moment: Int? = nil
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.roomChatSessionSource) private var sessionSource
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    var body: some View {
        if let code = store.challenge(challengeID)?.roomCode, let me = account.account {
            RoomChatConversation(scope: .init(accountID: me.id, roomCode: code),
                                 authorName: me.displayName, moment: moment, source: sessionSource)
                .id("\(sessionSource.identity):\(me.id):\(code)")
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

    init(scope: RoomChatScope, authorName: String, moment: Int?, source: RoomChatSessionSource) {
        self.authorName = authorName
        self.preview = source.preview
        _moment = State(initialValue: moment)
        _session = StateObject(wrappedValue: source.makeSession(scope: scope))
    }

    private func text(_ zh: String, _ en: String) -> String { language.resolved == .chinese ? zh : en }
    private var entries: [RoomChatEntry] { session.state?.orderedEntries ?? [] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if preview != nil {
                    Text(text("本地演示 · 不会发送给朋友", "Local demo · Nothing is sent to friends"))
                        .font(.caption).foregroundStyle(.secondary).padding(10)
                        .frame(maxWidth: .infinity).background(Color.blue.opacity(0.08))
                }
                if let error = session.error {
                    HStack {
                        Text(errorText(error)).font(.footnote)
                        if error == .fetch {
                            Button(text("重试", "Retry")) { Task { await session.refresh() } }
                        }
                    }.padding(12).frame(maxWidth: .infinity).background(Color.orange.opacity(0.12))
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if entries.isEmpty {
                                Text(text("在这里聊聊你们的故事", "Talk about your story here"))
                                    .foregroundStyle(.secondary).padding(.top, 48)
                            }
                            ForEach(entries) { entry in bubble(entry).id(entry.id) }
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
            .background(Color(.systemGroupedBackground))
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

    private func bubble(_ entry: RoomChatEntry) -> some View {
        let mine = entry.message.authorID == session.state?.scope.accountID
        return HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                Text(entry.message.authorName).font(.caption).foregroundStyle(.secondary)
                if let context = entry.message.moment {
                    Text(text("来自第 \(context) 个瞬间", "From moment \(context)"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(entry.message.text)
                    .textSelection(.enabled)
                    .padding(12)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .background(mine ? Color.oneDayBlue : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 16))
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
                }.font(.caption2).foregroundStyle(.secondary)
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let context = moment {
                HStack {
                    Text(text("聊聊第 \(context) 个瞬间", "About moment \(context)"))
                    Spacer()
                    Button(text("取消引用", "Remove context")) { moment = nil }
                }.font(.caption)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(text("发消息…", "Message…"), text: Binding(
                    get: { session.state?.draft ?? "" }, set: { session.setDraft($0) }), axis: .vertical)
                    .lineLimit(1...5).padding(12).background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18))
                    .disabled(session.state == nil)
                Button {
                    followsLatest = true
                    Task { await session.send(authorName: authorName, moment: moment) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 36))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(text("发送", "Send"))
                .disabled(session.state?.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false ||
                          (session.state?.draft.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > RoomChatState.maximumMessageLength)
            }
            if let count = session.state?.draft.count, count > 1_800 {
                Text("\(count) / \(RoomChatState.maximumMessageLength)")
                    .font(.caption).foregroundStyle(count > RoomChatState.maximumMessageLength ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(12).background(.regularMaterial)
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
