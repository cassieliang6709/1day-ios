import SwiftUI
import AVKit
import Photos

struct FinalReelView: View {
    let challenge: Challenge
    let clips: [DayClip]

    @State private var exportURL: URL?
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var isSavingVideo = false
    @State private var saveMessage: String?

    // Simple edit controls (Adjust sheet)
    @State private var showAdjust = false
    @State private var includeTitleCard = true
    @State private var includeCaptions = true
    @State private var fadeSeconds = 0.35

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let player, let url = exportURL {
                    VStack(spacing: 16) {
                        VideoPlayer(player: player)
                            .aspectRatio(
                                challenge.resolvedOrientation == .landscape ? 16 / 9 : 9 / 16,
                                contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 20))

                        Text(footerText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 10) {
                            ShareLink(item: url) {
                                Label(shareButtonTitle, systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            Button {
                                Task { await saveVideo(url) }
                            } label: {
                                Label(isSavingVideo ? Strings.saving : Strings.saveVideo, systemImage: "square.and.arrow.down")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(isSavingVideo)

                            if let saveMessage {
                                Text(saveMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        Strings.stitchFailed,
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text(Strings.stitching)
                            .font(.headline)
                        Text(Strings.renderedOnDevice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(Strings.filmTitle(oneDay: challenge.isOneDay))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdjust = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showAdjust) {
            AdjustSheet(
                includeTitleCard: $includeTitleCard,
                includeCaptions: $includeCaptions,
                fadeSeconds: $fadeSeconds
            ) {
                exportURL = nil
                Task { await render() }
            }
            .presentationDetents([.medium])
        }
        .task(id: renderRevision) { await render(force: true) }
        .onDisappear { player?.pause() }
    }

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    private var footerText: String {
        Strings.footerSequence(clips.count, unit: presenter.unitName)
    }

    private var shareButtonTitle: String {
        Strings.shareFilm(oneDay: challenge.isOneDay)
    }

    /// The exported film is derived data. Re-recording intentionally reuses
    /// the same file URL, so the clip URL alone cannot invalidate the render.
    /// Include every field burned into the film, especially `recordedAt`.
    private var renderRevision: [RenderRevision] {
        clips.map(RenderRevision.init)
    }

    private struct RenderRevision: Equatable {
        let id: String
        let url: URL
        let authorName: String?
        let label: String?
        let overlayText: String?
        let recordedAt: Date?
        let emoji: [String]
        let comments: [String]

        init(_ clip: DayClip) {
            id = clip.id
            url = clip.url
            authorName = clip.authorName
            label = clip.label
            overlayText = clip.overlayText
            recordedAt = clip.recordedAt
            emoji = clip.emoji
            comments = clip.comments
        }
    }

    private func render(force: Bool = false) async {
        let requestedRevision = renderRevision
        errorMessage = nil
        if !force, let cached = exportURL {
            play(cached)
            return
        }
        player?.pause()
        player = nil
        exportURL = nil
        do {
            var options = VideoStitcher.Options()
            options.crossfadeSeconds = fadeSeconds
            options.showDayCaptions = includeCaptions
            options.layout = challenge.isShared ? .friendsTogether : .sequential
            options.titleCard = includeTitleCard ? titleCard : nil
            let url = try await VideoStitcher.stitch(clips: clips, options: options)
            guard requestedRevision == renderRevision else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            exportURL = url
            play(url)
        } catch {
            guard requestedRevision == renderRevision else { return }
            print("[stitch] failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func play(_ url: URL) {
        let player = AVPlayer(url: url)
        self.player = player
        player.play()
    }

    private func saveVideo(_ url: URL) async {
        isSavingVideo = true
        saveMessage = nil
        defer { isSavingVideo = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveMessage = Strings.photosDenied
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            saveMessage = Strings.savedToPhotos
        } catch {
            saveMessage = Strings.saveFailed(error.localizedDescription)
        }
    }

    private var titleCard: VideoStitcher.TitleCard {
        let start = challenge.startDate
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let fmt = Date.FormatStyle()
            .month(.abbreviated).day()
            .locale(appLanguage.resolved.locale)
        if challenge.isOneDay {
            return VideoStitcher.TitleCard(
                title: challenge.title,
                subtitle: Strings.titleCardSubtitleOneDay(
                    clips.count, challenge.cards.count,
                    secondsLabel: challenge.resolvedClipLength.secondsLabel))
        }
        return VideoStitcher.TitleCard(
            title: challenge.title,
            subtitle: "\(start.formatted(fmt)) – \(end.formatted(fmt))")
    }
}

/// Lightweight editing controls: what goes into the render.
private struct AdjustSheet: View {
    @Binding var includeTitleCard: Bool
    @Binding var includeCaptions: Bool
    @Binding var fadeSeconds: Double
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        NavigationStack {
            Form {
                Section(Strings.overlays) {
                    Toggle(Strings.openingTitleCard, isOn: $includeTitleCard)
                    Toggle(Strings.dayCaptions, isOn: $includeCaptions)
                }
                Section {
                    HStack {
                        Text(Strings.transition)
                        Slider(value: $fadeSeconds, in: 0...0.6, step: 0.05)
                        Text(fadeSeconds == 0 ? Strings.cut : String(format: "%.2fs", fadeSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                } header: {
                    Text(Strings.sequence)
                } footer: {
                    Text(Strings.hardCutsFooter)
                }
            }
            .navigationTitle(Strings.adjust)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.apply) {
                        dismiss()
                        onApply()
                    }
                    .bold()
                }
            }
        }
    }
}
