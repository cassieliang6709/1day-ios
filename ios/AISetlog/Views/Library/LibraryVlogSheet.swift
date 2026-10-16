import Photos
import SwiftUI

/// A vlog from clips picked in 我的: any stories, any people. Opens on an
/// arrange step — the clips in the order they were picked, draggable, each
/// one previewable — and renders once 生成 vlog is tapped, in that order.
/// No shape picker: the cameras decide the shape, so the stitcher builds the
/// canvas from the takes themselves (`Options.aspect = nil`).
struct LibraryVlogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var order: [LibraryClip]
    @State private var stage: Stage = .arrange
    /// What the player lays out before the film is read; the film's own
    /// shape wins once it is.
    private let layoutRatio: CGFloat
    @State private var phase: Phase = .rendering
    @State private var saveMessage: String?
    @State private var isSaving = false
    /// The film remixed with music or voiceover; nil while it's the original.
    @State private var mixedURL: URL?
    @Environment(MoodStore.self) private var moodStore: MoodStore?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    enum Stage { case arrange, film }

    enum Phase: Equatable {
        case rendering
        case done(URL)
        case failed
    }

    init(clips: [LibraryClip]) {
        _order = State(initialValue: clips)
        layoutRatio = ClipLibrary.dominantAspect(of: clips).ratio
    }

    var body: some View {
        Group {
            switch stage {
            case .arrange:
                LibraryVlogArrange(order: $order) { stage = .film }
            case .film:
                film
            }
        }
        .background(OneDayCanvas().ignoresSafeArea())
        .task(id: stage) {
            if stage == .film { await render() }
        }
    }

    private var film: some View {
        VStack(spacing: 16) {
            HStack {
                IconBubble(systemName: "chevron.left") { stage = .arrange }
                    .accessibilityLabel(Strings.vlogArrangeTitle)
                Spacer()
                Text(Strings.vlogTitle)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Spacer()
                IconBubble(systemName: "xmark") { dismiss() }
            }

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
                    VlogPlayer(url: mixedURL ?? url, aspectRatio: layoutRatio)
                        .id(mixedURL ?? url)
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
                FilmSoundtrackPanel(
                    baseURL: url,
                    mood: order.first.flatMap { moodStore?.mood(on: $0.recordedAt)?.mood },
                    mixedURL: $mixedURL)
                Button {
                    Task { await save(mixedURL ?? url) }
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
    }

    private func render() async {
        phase = .rendering
        saveMessage = nil
        mixedURL = nil
        var options = VideoStitcher.Options()
        options.layout = .sequential
        options.aspect = nil
        do {
            let url = try await VideoStitcher.stitch(
                clips: ClipLibrary.stitchable(order), options: options)
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
