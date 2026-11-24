import Photos
import SwiftUI

struct LibraryVlogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var order: [LibraryClip]
    @State private var stage: Stage = .film
    @State private var renderedKey: String?
    private let layoutRatio: CGFloat
    @State private var phase: Phase = .rendering
    @State private var saveMessage: String?
    @State private var isSaving = false
    @State private var mixedURL: URL?
    @State private var showsSound = false
    @Environment(MoodStore.self) private var moodStore: MoodStore?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    enum Stage { case arrange, film }

    enum Phase: Equatable {
        case rendering
        case done(URL)
        case failed
    }

    private let title: String?

    init(clips: [LibraryClip], title: String? = nil) {
        self.title = title
        _order = State(initialValue: clips)
        layoutRatio = ClipLibrary.dominantAspect(of: clips).ratio
    }

    var body: some View {
        Group {
            switch stage {
            case .arrange:
                LibraryVlogArrange(order: $order, aspectRatio: layoutRatio) { stage = .film }
            case .film:
                film
            }
        }
        .background(OneDayCanvas().ignoresSafeArea())
        .task(id: stage) {
            guard stage == .film, renderedKey != orderKey else { return }
            await render()
        }
    }

    // Same shape as the room film page (FinalFilmTimeline): title and meta, big player, folded sound, Save / Share pinned at the bottom.
    private var film: some View {
        VStack(alignment: .leading, spacing: OneDay.Space.l) {
            HStack {
                Spacer()
                IconBubble(systemName: "xmark") { dismiss() }
            }

            VStack(alignment: .leading, spacing: OneDay.Space.xs) {
                if case .done = phase {
                    Text(Strings.filmReadyTitle)
                        .font(OneDay.Font.caption)
                        .foregroundStyle(OneDay.brandText)
                }
                Text(title ?? Strings.vlogTitle)
                    .font(OneDay.Font.title)
                    .foregroundStyle(OneDay.ink)
                Text(Strings.libraryClipCount(order.count))
                    .font(OneDay.Font.subhead)
                    .foregroundStyle(OneDay.inkSoft)
            }
            .accessibilityElement(children: .combine)

            Group {
                switch phase {
                case .rendering:
                    VStack(spacing: OneDay.Space.m) {
                        ProgressView().controlSize(.large)
                        Text(Strings.vlogMaking)
                            .font(OneDay.Font.subhead)
                            .foregroundStyle(OneDay.inkSoft)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .done(let url):
                    VlogPlayer(url: mixedURL ?? url, aspectRatio: layoutRatio)
                        .id(mixedURL ?? url)
                        .frame(maxWidth: .infinity)
                case .failed:
                    VStack(spacing: OneDay.Space.m) {
                        Text(Strings.vlogFailed)
                            .font(OneDay.Font.subhead)
                            .foregroundStyle(OneDay.inkSoft)
                        Button(Strings.vlogRetry) { Task { await render() } }
                            .buttonStyle(.primaryAction)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            if case .done(let url) = phase {
                if showsSound {
                    FilmSoundtrackPanel(
                        baseURL: url,
                        mood: order.first.flatMap { moodStore?.mood(on: $0.recordedAt)?.mood },
                        mixedURL: $mixedURL)
                } else {
                    HStack(spacing: OneDay.Space.m) {
                        if order.count > 1 {
                            Button { stage = .arrange } label: {
                                Label(Strings.vlogReorderAction, systemImage: "arrow.left.arrow.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.softAction)
                            .accessibilityIdentifier("library-vlog-reorder")
                        }
                        Button { showsSound = true } label: {
                            Label(Strings.filmAdjustTitle, systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.softAction)
                        .accessibilityIdentifier("library-vlog-adjust")
                    }
                }

                HStack(spacing: OneDay.Space.m) {
                    Button {
                        Task { await save(mixedURL ?? url) }
                    } label: {
                        HStack(spacing: OneDay.Space.s) {
                            if isSaving { ProgressView().tint(OneDay.onBrand) } else { Image(systemName: "square.and.arrow.down") }
                            Text(Strings.saveAction)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(isSaving)
                    .accessibilityIdentifier("library-vlog-save")

                    ShareLink(item: mixedURL ?? url) {
                        Label(Strings.shareAction, systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.softAction)
                    .accessibilityIdentifier("library-vlog-share")
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(OneDay.Font.caption)
                        .foregroundStyle(OneDay.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(OneDay.Space.xl)
        .animation(OneDay.Motion.soft, value: showsSound)
    }

    private var orderKey: String { order.map(\.id).joined(separator: "|") }

    private func render() async {
        phase = .rendering
        saveMessage = nil
        mixedURL = nil
        var options = VideoStitcher.Options()
        options.layout = .sequential
        options.aspect = nil
        do {
            let url = try await BackgroundFilmExport.shared.render(
                clips: ClipLibrary.stitchable(order), options: options)
            guard !Task.isCancelled else { return }
            phase = .done(url)
            renderedKey = orderKey
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

struct VlogRequest: Identifiable {
    let clips: [LibraryClip]
    var title: String? = nil
    var id: String { clips.map(\.id).joined(separator: "|") }
}
