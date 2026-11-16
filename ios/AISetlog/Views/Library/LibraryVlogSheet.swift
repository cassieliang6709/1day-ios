import Photos
import SwiftUI

struct LibraryVlogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var order: [LibraryClip]
    @State private var retryRevision = 0
    @State private var stage: Stage = .arrange
    private let layoutRatio: CGFloat
    @State private var phase: Phase = .rendering
    @State private var renderError: String?
    @State private var saveMessage: String?
    @State private var isSaving = false
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
        .task(id: "\(stage)-\(retryRevision)") {
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
                        Text(renderError ?? Strings.vlogFailed)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                        Button(Strings.vlogRetry) { retryRevision += 1 }
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
        renderError = nil
        saveMessage = nil
        mixedURL = nil
        var options = VideoStitcher.Options()
        options.layout = .sequential
        options.aspect = nil
        do {
            let url = try await BackgroundFilmExport.shared.render(
                clips: ClipLibrary.stitchable(order), options: options)
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            phase = .done(url)
        } catch {
            guard !Task.isCancelled else { return }
            print("[library] vlog failed: \(error)")
            switch error {
            case VideoStitcher.StitchError.inputTooLarge: renderError = Strings.filmInputTooLarge
            case VideoExportOperation.Failure.timedOut: renderError = Strings.filmExportTimedOut
            default: break
            }
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
