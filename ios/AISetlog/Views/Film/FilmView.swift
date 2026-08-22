import SwiftUI
import AVKit
import Photos

/// Screens 5 and 6 — the film being made, then the film.
///
/// One view, two phases, because they're one moment for the user: you finish
/// the day and the film assembles in front of you. Stitching used to be a bare
/// spinner; here the wait *is* content — you watch your moments being folded
/// in one by one, which is the payoff the whole app builds toward.
struct FilmView: View {
    let challenge: Challenge
    let clips: [DayClip]

    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var saveMessage: String?
    /// How far the staged progress animation has got. Cosmetic — the stitcher
    /// gives no progress callbacks, so this paces the copy honestly by naming
    /// what is actually happening rather than claiming a percentage.
    @State private var stage = 0
    @State private var showAdjust = false
    @State private var includeTitleCard = true
    @State private var includeCaptions = true
    @State private var fadeSeconds = 0.35

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var schedule: StorySchedule { StorySchedule(challenge) }

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 3)

            if let exportURL {
                FinalFilmTimeline(
                    challenge: challenge,
                    clips: clips,
                    filmURL: exportURL,
                    isSaving: isSaving,
                    saveMessage: saveMessage,
                    onSave: { Task { await saveToPhotos(exportURL) } },
                    onAdjust: { showAdjust = true })
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let errorMessage {
                failure(errorMessage)
            } else {
                GeneratingFilm(
                    challenge: challenge,
                    clips: clips,
                    stage: stage)
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            IconBubble(systemName: "chevron.left") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
        .sheet(isPresented: $showAdjust) {
            AdjustFilmSheet(
                includeTitleCard: $includeTitleCard,
                includeCaptions: $includeCaptions,
                fadeSeconds: $fadeSeconds
            ) {
                withAnimation(OneDay.Motion.soft) { exportURL = nil }
                Task { await render() }
            }
            .presentationDetents([.medium])
        }
        .task(id: renderRevision) { await render() }
    }

    // MARK: - Failure

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(Color.oneDayButter)
            Text(Strings.stitchFailed)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .multilineTextAlignment(.center)
            Button(Strings.rebuildFilm) {
                Task { await render() }
            }
            .buttonStyle(.softAction)
            .padding(.top, 4)
        }
        .padding(28)
        .glassSurface(radius: OneDay.Radius.hero)
        .padding(.horizontal, 28)
    }

    // MARK: - Rendering

    /// The exported film is derived data. Re-recording reuses the same file
    /// URL, so the clip URL alone cannot invalidate a render — include every
    /// field that gets burned into the frames.
    private var renderRevision: [RenderRevision] {
        clips.map(RenderRevision.init) + [
            RenderRevision(
                options: "\(includeTitleCard)-\(includeCaptions)-\(fadeSeconds)")
        ]
    }

    private struct RenderRevision: Equatable {
        var id = ""
        var url: URL?
        var authorName: String?
        var label: String?
        var overlayText: String?
        var recordedAt: Date?
        var emoji: [String] = []
        var comments: [String] = []
        var options: String = ""

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

        init(options: String) {
            self.options = options
        }
    }

    private func render() async {
        let requested = renderRevision
        errorMessage = nil
        exportURL = nil
        stage = 0
        let ticker = Task { await advanceStages() }
        defer { ticker.cancel() }

        do {
            var options = VideoStitcher.Options()
            options.crossfadeSeconds = fadeSeconds
            options.showDayCaptions = includeCaptions
            options.layout = challenge.isShared ? .friendsTogether : .sequential
            options.titleCard = includeTitleCard ? titleCard : nil
            let url = try await VideoStitcher.stitch(clips: clips, options: options)
            // A newer render started while this one was working.
            guard requested == renderRevision else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            withAnimation(OneDay.Motion.soft) { exportURL = url }
        } catch {
            guard requested == renderRevision else { return }
            print("[stitch] failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Walks the four named steps while the stitcher works. Stops short of the
    /// last one so the copy never claims to be finished before it is.
    private func advanceStages() async {
        for step in 1...3 {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(OneDay.Motion.soft) { stage = step }
        }
    }

    private var titleCard: VideoStitcher.TitleCard {
        let start = challenge.startDate
        let end = Calendar.current.date(
            byAdding: .day, value: max(challenge.cards.count - 1, 0), to: start) ?? start
        let fmt = Date.FormatStyle()
            .month(.abbreviated).day().locale(appLanguage.resolved.locale)
        if challenge.isOneDay {
            return VideoStitcher.TitleCard(
                title: presenter.displayTitle,
                subtitle: Strings.titleCardSubtitleOneDay(
                    clips.count, challenge.cards.count,
                    secondsLabel: challenge.resolvedClipLength.secondsLabel))
        }
        return VideoStitcher.TitleCard(
            title: presenter.displayTitle,
            subtitle: "\(start.formatted(fmt)) – \(end.formatted(fmt))")
    }

    // MARK: - Saving

    private func saveToPhotos(_ url: URL) async {
        isSaving = true
        saveMessage = nil
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
            saveMessage = Strings.savedToPhotos
        } catch {
            saveMessage = Strings.saveFailed(error.localizedDescription)
        }
    }
}

// MARK: - Adjust

/// What goes into the render. Kept as a plain form — it's a settings sheet,
/// and dressing it up would only make it harder to scan.
private struct AdjustFilmSheet: View {
    @Binding var includeTitleCard: Bool
    @Binding var includeCaptions: Bool
    @Binding var fadeSeconds: Double
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
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
            .tint(Color.oneDayBlue)
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
