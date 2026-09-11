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
    @State private var selected: PhotosPickerItem?
    @State private var showPicker = false
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 4) {
            Menu(chinese ? "替换成员视频（前3秒）" : "Replace member clip (first 3s)") {
                ForEach(runtime.store.recordedClips(for: runtime.challengeID)) { clip in
                    Button(clip.authorName ?? "Sample") {
                        target = clip.authorID
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
                try await runtime.replaceClip(authorID: target, from: movie.url)
                guard !Task.isCancelled, !runtime.isClosed else { return }
                didReplace()
            } catch {
                if !Task.isCancelled, !runtime.isClosed { failed = true }
            }
        }
    }
}
#endif
