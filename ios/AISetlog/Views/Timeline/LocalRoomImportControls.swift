#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

/// A video off the camera roll, copied somewhere this build can read it.
///
/// `PhotosPickerItem` hands back a file it owns and deletes out from under you,
/// so the copy is the point. The caller deletes it once the fixture has taken
/// what it needs.
struct RoomDemoMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("room-demo-picker-\(UUID())")
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: url)
            return RoomDemoMovie(url: url)
        }
    }
}

/// Fixture controls only. The room underneath remains the production UI.
struct LocalRoomImportControls: View {
    let runtime: LocalRoomRuntime
    let chinese: Bool
    let didReplace: () -> Void
    @State private var target: String?
    @State private var targetDay: Int?
    @State private var selected: PhotosPickerItem?
    @State private var showPicker = false
    @State private var busy = false
    @State private var failed = false

    /// Who, and — once the room has more than one slot — which moment. With
    /// three moments and two members the menu is six rows, and three of them
    /// say the same name; the moment is what tells them apart.
    private func label(for clip: DayClip, multiSlot: Bool) -> String {
        let who = clip.authorName ?? "Sample"
        guard multiSlot else { return who }
        let challenge = runtime.store.challenges.first { $0.id == runtime.challengeID }
        let what = challenge?.momentValue(forSlot: clip.day) ?? "\(clip.day)"
        return "\(who) · \(what)"
    }

    var body: some View {
        let clips = runtime.store.recordedClips(for: runtime.challengeID)
        let multiSlot = Set(clips.map(\.day)).count > 1
        return VStack(spacing: 4) {
            Menu(chinese ? "替换成员视频（前3秒）" : "Replace member clip (first 3s)") {
                ForEach(clips) { clip in
                    Button(label(for: clip, multiSlot: multiSlot)) {
                        target = clip.authorID
                        targetDay = clip.day
                        selected = nil
                        failed = false
                        showPicker = true
                    }
                }
            }
            .disabled(busy)
            .accessibilityIdentifier("local-room-import")
            if busy { ProgressView(chinese ? "正在导入…" : "Importing…") }
            if failed {
                Text(chinese ? "导入失败，原视频未改动。请重新选择。" : "Import failed. Clips unchanged. Choose again.")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(6)
        .photosPicker(isPresented: $showPicker, selection: $selected, matching: .videos)
        .task(id: selected) {
            guard let selected, let target else { return }
            busy = true
            failed = false
            defer { busy = false }
            do {
                guard let movie = try await selected.loadTransferable(type: RoomDemoMovie.self) else {
                    throw LocalRoomRuntime.Failure.media
                }
                defer { try? FileManager.default.removeItem(at: movie.url) }
                try Task.checkCancellation()
                try await runtime.replaceClip(authorID: target, day: targetDay, from: movie.url)
                guard !Task.isCancelled, !runtime.isClosed else { return }
                didReplace()
            } catch {
                if !Task.isCancelled, !runtime.isClosed { failed = true }
            }
        }
    }
}
#endif
