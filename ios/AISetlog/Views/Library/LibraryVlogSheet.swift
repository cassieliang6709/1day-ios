import Photos
import SwiftUI

/// A vlog from clips picked in 我的: any stories, any people, in the order they
/// were filmed. Renders on open with the shape most of the clips were shot in;
/// changing the shape renders again.
struct LibraryVlogSheet: View {
    let clips: [LibraryClip]

    @Environment(\.dismiss) private var dismiss
    @State private var aspect: VideoStitcher.Aspect
    @State private var phase: Phase = .rendering
    @State private var saveMessage: String?
    @State private var isSaving = false

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    enum Phase: Equatable {
        case rendering
        case done(URL)
        case failed
    }

    init(clips: [LibraryClip]) {
        self.clips = clips
        _aspect = State(initialValue: ClipLibrary.dominantAspect(of: clips))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(Strings.vlogTitle)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Spacer()
                IconBubble(systemName: "xmark") { dismiss() }
            }

            Picker(Strings.vlogShape, selection: $aspect) {
                ForEach(VideoStitcher.Aspect.allCases) { option in
                    Text(Strings.orientationName(orientation(option))).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(phase == .rendering)

            Group {
                switch phase {
                case .rendering:
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text(Strings.vlogMaking)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .done(let url):
                    VlogPlayer(url: url, aspectRatio: aspect.ratio)
                        .id(url)
                case .failed:
                    VStack(spacing: 12) {
                        Text(Strings.vlogFailed)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                        Button(Strings.vlogRetry) { Task { await render() } }
                            .buttonStyle(.primaryAction)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            if case .done(let url) = phase {
                Button {
                    Task { await save(url) }
                } label: {
                    if isSaving { ProgressView().tint(.white) } else { Text(Strings.saveVlogToPhotos) }
                }
                .buttonStyle(.primaryAction)
                .disabled(isSaving)

                if let saveMessage {
                    Text(saveMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                }
            }
        }
        .padding(20)
        .background(OneDayCanvas().ignoresSafeArea())
        .task(id: aspect) { await render() }
    }

    private func orientation(_ aspect: VideoStitcher.Aspect) -> Challenge.Orientation {
        switch aspect {
        case .portrait: .portrait
        case .landscape: .landscape
        case .square: .square
        }
    }

    private func render() async {
        phase = .rendering
        saveMessage = nil
        var options = VideoStitcher.Options()
        options.layout = .sequential
        options.aspect = aspect
        do {
            let url = try await VideoStitcher.stitch(
                clips: ClipLibrary.stitchable(clips), options: options)
            guard !Task.isCancelled else { return }
            phase = .done(url)
        } catch {
            guard !Task.isCancelled else { return }
            print("[library] vlog failed: \(error)")
            phase = .failed
        }
    }

    private func save(_ url: URL) async {
        isSaving = true
        defer { isSaving = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveMessage = Strings.photosDenied
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            saveMessage = Strings.savedToPhotos
        } catch {
            saveMessage = Strings.saveFailed
        }
    }
}
