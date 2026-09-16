#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import SwiftUI

/// The demo uses the production room, moment preview, film and chat views.
/// Only this outer shell chooses fixtures and explains the local-only boundary.
struct LocalRoomDemoView: View {
    let chinese: Bool
    @StateObject private var owner = LocalRoomDemoOwner()
    @State private var members = 2
    @State private var retry = 0
    @State private var clipRevision = 0

    var body: some View {
        VStack(spacing: 0) {
            Text(chinese ? "本地示例 · 不上传房间，不保存或分享" : "Local sample · No room uploads, saving or sharing")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(8)
                .accessibilityIdentifier("local-room-notice")
            Picker(chinese ? "示例人数" : "Sample members", selection: $members) {
                Text(chinese ? "两人" : "Two people").tag(2)
                Text(chinese ? "三人" : "Three people").tag(3)
            }.pickerStyle(.segmented).padding(.horizontal)
                .accessibilityIdentifier("local-room-members")
            if let runtime = owner.runtime, let media = owner.media {
                LocalRoomImportControls(runtime: runtime, chinese: chinese) { clipRevision += 1 }
                    .id(runtime.challengeID)
                NavigationStack {
                    StoryTimelineView(challengeID: runtime.challengeID)
                }
                .environment(runtime.store)
                .environment(runtime.account)
                .environment(runtime.drafts)
                .environment(\.roomChatSessionSource, .local(runtime.chat))
                .environment(\.roomPreviewMediaScope, media)
                .defaultAppStorage(runtime.preferences)
                .id("\(runtime.challengeID)-\(clipRevision)")
                .accessibilityIdentifier("local-formal-room")
            } else if owner.failed {
                VStack(spacing: 16) {
                    Text(chinese ? "示例生成失败，未改动真实房间。" : "Sample generation failed. Your rooms are unchanged.")
                    Button(chinese ? "重试" : "Retry") { retry += 1 }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView(chinese ? "正在生成本地视频…" : "Generating local clips…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(LocalRoomRemovalObserver(onRemove: owner.close).frame(width: 0, height: 0))
        .task(id: "\(members)-\(retry)") { await owner.load(memberCount: members, chinese: chinese) }
    }
}

@MainActor
final class LocalRoomDemoOwner: ObservableObject {
    @Published private(set) var runtime: LocalRoomRuntime?
    @Published private(set) var media: RoomPreviewMediaScope?
    @Published private(set) var failed = false
    private var revision = 0
    private(set) var isClosed = false

    func load(memberCount: Int, chinese: Bool) async {
        guard !isClosed else { return }
        revision += 1
        let requested = revision
        runtime?.close()
        media?.close()
        runtime = nil
        media = nil
        failed = false
        do {
            let next = try await LocalRoomRuntime.make(memberCount: memberCount, chinese: chinese)
            guard !Task.isCancelled, !isClosed, revision == requested else { next.close(); return }
            next.preferences.set(chinese ? AppLanguage.chinese.rawValue : AppLanguage.english.rawValue,
                                 forKey: AppLanguage.storageKey)
            media = RoomPreviewMediaScope()
            runtime = next
        } catch {
            guard !Task.isCancelled, !isClosed, revision == requested else { return }
            failed = true
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        revision += 1
        runtime?.close()
        media?.close()
        runtime = nil
        media = nil
    }
}

/// Dismantling means this shell was removed. onDisappear is intentionally NOT
/// used: full-screen moment/camera previews may temporarily cover the room.
private struct LocalRoomRemovalObserver: UIViewRepresentable {
    let onRemove: () -> Void
    final class Coordinator {
        let onRemove: () -> Void
        init(onRemove: @escaping () -> Void) { self.onRemove = onRemove }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onRemove: onRemove) }
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ uiView: UIView, context: Context) {}
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // SwiftUI is still dismantling its graph. Runtime cleanup publishes
        // store changes, so perform it on the next main turn, not mid-update.
        DispatchQueue.main.async { coordinator.onRemove() }
    }
}
#endif
