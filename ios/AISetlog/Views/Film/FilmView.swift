import SwiftUI
import AVKit
import Photos

enum FilmRenderOutcome: Equatable {
    case film
    case failed
    case sessionEnded
    case superseded

    static func of(
        stitchFailed: Bool,
        superseded: Bool,
        scopeRejected: Bool,
        scopeClosed: Bool
    ) -> FilmRenderOutcome {
        if superseded { return .superseded }
        if stitchFailed { return scopeClosed ? .sessionEnded : .failed }
        if scopeRejected { return .sessionEnded }
        return .film
    }

    var showsSomething: Bool { self != .superseded }
}

struct FilmView: View {
    let challenge: Challenge
    let clips: [DayClip]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomPreviewMediaScope) private var previewMedia
    @Environment(AccountStore.self) private var account

    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var photosDenied = false
    @State private var isSaved = false
    @State private var stage = 0
    @State private var renderProgress: Double = 0
    @State private var canRenderInBackground = false
    @State private var showAdjust = false
    @State private var adjustments = FilmAdjustments()
    @State private var selection: FilmSelection
    @State private var filterTarget: FilmFilterTarget?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @AppStorage(PersonalEffectParameters.storageKey) private var look: PersonalEffectParameters = .none

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var schedule: StorySchedule { StorySchedule(challenge) }

    init(challenge: Challenge, clips: [DayClip]) {
        self.challenge = challenge
        self.clips = clips
        _selection = State(initialValue: challenge.isShared
            ? FilmSelectionStore.load(for: challenge.id) : FilmSelection())
    }

    private var people: [FilmPerson] {
        challenge.isShared ? FilmPerson.people(in: clips) : []
    }

    private var filmClips: [DayClip] {
        challenge.isShared ? selection.applied(to: clips) : clips
    }

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 3)

            if let exportURL {
                FinalFilmTimeline(
                    challenge: challenge,
                    clips: filmClips,
                    filmURL: exportURL,
                    isSaving: isSaving,
                    isSaved: isSaved,
                    saveMessage: saveMessage,
                    onOpenSettings: photosDenied ? openSystemSettings : nil,
                    onSave: { url in Task { await saveToPhotos(url) } },
                    onAdjust: { showAdjust = true },
                    people: people,
                    selection: selection,
                    onFilter: { filterTarget = $0 })
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let errorMessage {
                failure(errorMessage)
            } else {
                GeneratingFilm(
                    challenge: challenge,
                    clips: filmClips,
                    stage: stage,
                    progress: previewMedia == nil ? renderProgress : nil,
                    canContinueInBackground: previewMedia == nil ? canRenderInBackground : nil)
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            IconBubble(systemName: "chevron.left") { dismiss() }
                .accessibilityLabel(Text(Strings.back))
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
        .sheet(isPresented: $showAdjust) {
            AdjustFilmSheet(initial: adjustments) { adjustments = $0 }
                .presentationDetents([.medium])
        }
        .sheet(item: $filterTarget) { target in
            FilmFilterSheet(people: people, selection: selection, target: target) { picked in
                let kept = picked.pruned(to: clips)
                selection = kept
                FilmSelectionStore.save(kept, for: challenge.id)
            }
        }
        .task(id: renderRevision) { await render() }
        .task(id: saveMessage) {
            guard saveMessage != nil, !photosDenied else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(OneDay.Motion.soft) { saveMessage = nil }
        }
    }


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


    private var renderRevision: [RenderRevision] {
        let held = challenge.isShared ? selection.freezeFrames(for: clips) : [:]
        let holds = held.sorted { $0.key < $1.key }
            .map { "\($0.key)@\(String(format: "%.3f", $0.value))" }
            .joined(separator: ",")
        return filmClips.map(RenderRevision.init) + [
            RenderRevision(
                options: "\(adjustments.includeTitleCard)-\(adjustments.includeCaptions)"
                    + "-\(adjustments.fadeSeconds)-\(look.rawValue)-hold[\(holds)]"
                    + "-order[\(selection.dayOrder.map(String.init).joined(separator: ","))]")
        ]
    }

    private var cacheContext: String {
        let card = adjustments.includeTitleCard ? "\(titleCard.title)|\(titleCard.subtitle)" : ""
        return "\(card)|\(challenge.isShared)|\(challenge.isTimeOnly)|\(account.account?.id ?? "")"
    }

    fileprivate struct RenderRevision: Equatable {
        var id = ""
        var url: URL?
        var authorName: String?
        var label: String?
        var overlayText: String?
        var captionSticker: CaptionSticker?
        var captions: [Caption] = []
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
            captionSticker = clip.captionSticker
            captions = clip.captions
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
        let context = cacheContext
        errorMessage = nil
        isSaved = false
        saveMessage = nil

        if previewMedia == nil,
           let cached = FilmRenderCache.film(
               for: challenge.id, revision: requested, context: context) {
            exportURL = cached
            return
        }

        exportURL = nil
        stage = 0
        renderProgress = 0
        let ticker = Task { await advanceStages() }
        defer { ticker.cancel() }

        do {
            var options = VideoStitcher.Options()
            options.crossfadeSeconds = adjustments.fadeSeconds
            options.showDayCaptions = adjustments.includeCaptions && !challenge.isTimeOnly
            options.layout = challenge.isShared ? .friendsTogether : .sequential
            options.titleCard = adjustments.includeTitleCard ? titleCard : nil
            options.look = look
            options.lookAuthorID = challenge.isShared ? (account.account?.id ?? "local") : nil
            if challenge.isShared {
                options.keptClipIDs = Set(filmClips.map(\.id))
                options.freezeFrames = selection.freezeFrames(for: clips)
                if !selection.dayOrder.isEmpty { options.dayOrder = selection.dayOrder }
            }
            let url: URL
            if previewMedia == nil {
                url = try await BackgroundFilmExport.shared.render(clips: clips, options: options) { fraction, background in
                    guard requested == renderRevision else { return }
                    renderProgress = fraction
                    canRenderInBackground = background
                }
            } else {
                url = try await VideoStitcher.stitch(clips: clips, options: options)
            }
            let rejected = previewMedia.map { !$0.accept(url) } ?? false
            let superseded = requested != renderRevision
            if previewMedia == nil, !superseded {
                FilmRenderCache.store(
                    url, for: challenge.id, revision: requested, context: context)
            }
            apply(
                FilmRenderOutcome.of(
                    stitchFailed: false,
                    superseded: superseded,
                    scopeRejected: rejected,
                    scopeClosed: previewMedia?.isClosed == true),
                url: url)
        } catch {
            print("[stitch] failed: \(error)")
            apply(
                FilmRenderOutcome.of(
                    stitchFailed: true,
                    superseded: requested != renderRevision,
                    scopeRejected: false,
                    scopeClosed: previewMedia?.isClosed == true),
                url: nil)
        }
    }

    private func apply(_ outcome: FilmRenderOutcome, url: URL?) {
        switch outcome {
        case .superseded:
            if let url { try? FileManager.default.removeItem(at: url) }
        case .film:
            guard let url else { errorMessage = Strings.filmFailedTryAgain; return }
            withAnimation(OneDay.Motion.soft) { exportURL = url }
        case .sessionEnded:
            errorMessage = Strings.filmSessionEnded
        case .failed:
            errorMessage = Strings.filmFailedTryAgain
        }
    }

    private func advanceStages() async {
        for step in 1..<GeneratingFilm.stepCount {
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
                    filmClips.count, challenge.cards.count,
                    secondsLabel: challenge.resolvedClipLength.secondsLabel))
        }
        return VideoStitcher.TitleCard(
            title: presenter.displayTitle,
            subtitle: "\(start.formatted(fmt)) – \(end.formatted(fmt))")
    }


    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func saveToPhotos(_ url: URL) async {
        guard previewMedia == nil else { return }
        isSaving = true
        saveMessage = nil
        defer { isSaving = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveMessage = Strings.photosDenied
            photosDenied = true
            return
        }
        photosDenied = false
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSaved = true
            saveMessage = Strings.savedToPhotos
        } catch {
            print("[film] save to Photos failed: \(error)")
            saveMessage = Strings.saveFailed
        }
    }
}


struct FilmAdjustments: Equatable {
    var includeTitleCard = true
    var includeCaptions = true
    var fadeSeconds = 0.35
}

private struct AdjustFilmSheet: View {
    let onApply: (FilmAdjustments) -> Void

    @State private var draft: FilmAdjustments

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    init(initial: FilmAdjustments, onApply: @escaping (FilmAdjustments) -> Void) {
        self.onApply = onApply
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(Strings.overlays) {
                    Toggle(Strings.openingTitleCard, isOn: $draft.includeTitleCard)
                    Toggle(Strings.dayCaptions, isOn: $draft.includeCaptions)
                }
                Section {
                    HStack {
                        Text(Strings.transition)
                        Slider(value: $draft.fadeSeconds, in: 0...0.6, step: 0.05)
                        Text(draft.fadeSeconds == 0
                            ? Strings.cut : String(format: "%.2fs", draft.fadeSeconds))
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
            .tint(Color.oneDayBrand)
            .navigationTitle(Strings.adjust)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.apply) {
                        onApply(draft)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}


@MainActor
private enum FilmRenderCache {
    private struct Entry {
        let revision: [FilmView.RenderRevision]
        let context: String
        let url: URL
    }

    private static var entries: [UUID: Entry] = [:]

    static func film(
        for story: UUID, revision: [FilmView.RenderRevision], context: String
    ) -> URL? {
        guard let entry = entries[story],
              entry.revision == revision,
              entry.context == context,
              FileManager.default.fileExists(atPath: entry.url.path)
        else { return nil }
        return entry.url
    }

    static func store(
        _ url: URL, for story: UUID, revision: [FilmView.RenderRevision], context: String
    ) {
        if let old = entries[story]?.url, old != url {
            try? FileManager.default.removeItem(at: old)
        }
        entries[story] = Entry(revision: revision, context: context, url: url)
    }
}
