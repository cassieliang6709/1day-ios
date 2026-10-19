import SwiftUI
import AVKit
import Photos

/// What a finished stitch turns into on screen.
///
/// Exists because the bug it replaces was an *absence*: `render()` had three
/// paths that returned without setting either `exportURL` or `errorMessage`,
/// and each one left the view on `GeneratingFilm` with nothing on the way — a
/// spinner that could not finish. Nothing about a bare `return` says that, so
/// the rule is a type now: every case either shows a film or says why not, and
/// `.superseded` is the single case allowed to show nothing, because by
/// definition another render is already running.
enum FilmRenderOutcome: Equatable {
    /// Show the film.
    case film
    /// Show `failure(_:)`. The stitch produced nothing usable.
    case failed
    /// Show `failure(_:)` with the demo's own wording: the stitch worked, but
    /// the session that owned the media closed underneath it.
    case sessionEnded
    /// Show nothing and keep waiting — `renderRevision` moved, so the render
    /// that replaced this one owns the screen.
    case superseded

    /// - Parameters:
    ///   - stitchFailed: the stitcher threw.
    ///   - superseded: `requested != renderRevision` — a newer render started.
    ///   - scopeRejected: the room-preview media scope refused the output, which
    ///     it does whenever it has closed.
    ///   - scopeClosed: the scope is closed. Only consulted when the stitch
    ///     failed, to choose the honest wording.
    static func of(
        stitchFailed: Bool,
        superseded: Bool,
        scopeRejected: Bool,
        scopeClosed: Bool
    ) -> FilmRenderOutcome {
        // First, because it is the only reason silence is correct.
        if superseded { return .superseded }
        if stitchFailed { return scopeClosed ? .sessionEnded : .failed }
        if scopeRejected { return .sessionEnded }
        return .film
    }

    /// The invariant the bug broke. Anything that isn't `.superseded` has to
    /// put something on screen.
    var showsSomething: Bool { self != .superseded }
}

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
    @Environment(\.roomPreviewMediaScope) private var previewMedia
    /// Read only to know whose clips the grade is allowed to touch.
    @Environment(AccountStore.self) private var account

    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var saveMessage: String?
    /// Whether the last save was refused for want of photo-library access —
    /// the only saveMessage iOS Settings can do something about.
    @State private var photosDenied = false
    /// This render is in Photos. Cleared by the next render, which is a
    /// different file and so genuinely not saved yet.
    @State private var isSaved = false
    /// How far the staged progress animation has got. Cosmetic — the stitcher
    /// gives no progress callbacks, so this paces the copy honestly by naming
    /// what is actually happening rather than claiming a percentage.
    @State private var stage = 0
    @State private var showAdjust = false
    /// What goes into the render. Written only by the Adjust sheet's Apply —
    /// see `AdjustFilmSheet` for why the sheet edits a copy.
    @State private var adjustments = FilmAdjustments()

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    /// The film gets whatever you've been watching your clips in. It isn't
    /// asked again at save time: you already answered by looking.
    @AppStorage(PersonalEffectParameters.storageKey) private var look: PersonalEffectParameters = .none

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
                    isSaved: isSaved,
                    saveMessage: saveMessage,
                    onOpenSettings: photosDenied ? openSystemSettings : nil,
                    onSave: { url in Task { await saveToPhotos(url) } },
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
                .accessibilityLabel(Text(Strings.back))
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
        .sheet(isPresented: $showAdjust) {
            // Apply only writes the values back. `renderRevision` includes
            // them, so the `.task` below notices and re-renders once; the
            // explicit `render()` this used to call on top of that started a
            // second export of the same film racing the first.
            AdjustFilmSheet(initial: adjustments) { adjustments = $0 }
                .presentationDetents([.medium])
        }
        .task(id: renderRevision) { await render() }
        // A toast, not a status line: "saved" is news for a moment and then
        // it's the button's job (已保存) to remember. A permission refusal
        // stays, because it carries the way to Settings.
        .task(id: saveMessage) {
            guard saveMessage != nil, !photosDenied else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(OneDay.Motion.soft) { saveMessage = nil }
        }
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
                options: "\(adjustments.includeTitleCard)-\(adjustments.includeCaptions)"
                    + "-\(adjustments.fadeSeconds)-\(look.rawValue)")
        ]
    }

    /// Everything else that ends up in the frames: the title card's words,
    /// which follow the story's name and the app language, and the room
    /// layout. Not part of `renderRevision`, so changing them doesn't restart a
    /// render mid-flight — but a cached film made with different ones is a
    /// different film.
    private var cacheContext: String {
        let card = adjustments.includeTitleCard ? "\(titleCard.title)|\(titleCard.subtitle)" : ""
        return "\(card)|\(challenge.isShared)|\(challenge.isTimeOnly)|\(account.account?.id ?? "")"
    }

    /// File-private rather than private so `FilmRenderCache` can hold one.
    fileprivate struct RenderRevision: Equatable {
        var id = ""
        var url: URL?
        var authorName: String?
        var label: String?
        var overlayText: String?
        /// Where those words are burned. Moving a caption changes the frames
        /// without changing anything else, so a stale film has to be noticed
        /// here or the old one gets handed back.
        var captionSticker: CaptionSticker?
        /// Every caption, for the same reason: adding a second one changes the
        /// frames and leaves the first one's words and place alone.
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

        // Same story, same footage, same settings as a film this session
        // already made: show that one. Opening the film used to re-export it
        // every time, so backing out to check a clip and coming straight back
        // cost the whole wait again. Never for the sample room, whose scope
        // owns — and deletes — its files.
        if previewMedia == nil,
           let cached = FilmRenderCache.film(
               for: challenge.id, revision: requested, context: context) {
            exportURL = cached
            return
        }

        exportURL = nil
        stage = 0
        let ticker = Task { await advanceStages() }
        defer { ticker.cancel() }

        do {
            var options = VideoStitcher.Options()
            options.crossfadeSeconds = adjustments.fadeSeconds
            options.showDayCaptions = adjustments.includeCaptions && !challenge.isTimeOnly
            options.layout = challenge.isShared ? .friendsTogether : .sequential
            options.titleCard = adjustments.includeTitleCard ? titleCard : nil
            options.look = look
            // Solo films are all yours, so the grade is unrestricted; in a
            // shared room it stops at your own takes.
            options.lookAuthorID = challenge.isShared ? (account.account?.id ?? "local") : nil
            let url = try await VideoStitcher.stitch(clips: clips, options: options)
            // The scope refuses — and deletes — anything handed to it after it
            // closes, which is what 退出演示 does. Asked before the outcome is
            // computed so the answer is part of the decision rather than an
            // early return around it.
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

    /// Puts the outcome on screen. The one place `exportURL` and `errorMessage`
    /// are written after a render, so "always one or the other" is checkable by
    /// reading a single function instead of three `return`s.
    ///
    /// A failure says the same fixed sentence whatever went wrong. It used to
    /// print `error.localizedDescription`, which is AVFoundation talking to
    /// itself ("The operation could not be completed (AVFoundationErrorDomain
    /// error -11800)"); the raw error is logged in `render()` instead.
    private func apply(_ outcome: FilmRenderOutcome, url: URL?) {
        switch outcome {
        case .superseded:
            // Another render owns the screen and will land its own result.
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

    /// Walks the named steps while the stitcher works, and parks on the last
    /// one — 导出 — with its spinner still turning. `GeneratingFilm` only ticks
    /// a step once the *next* one has started, so the export is never shown
    /// as done; the screen leaving is what says that.
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
                    clips.count, challenge.cards.count,
                    secondsLabel: challenge.resolvedClipLength.secondsLabel))
        }
        return VideoStitcher.TitleCard(
            title: presenter.displayTitle,
            subtitle: "\(start.formatted(fmt)) – \(end.formatted(fmt))")
    }

    // MARK: - Saving

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func saveToPhotos(_ url: URL) async {
        // Local previews do not write into the user's photo library.
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
            // The film leaving the app is the one moment worth feeling. The
            // toast alone is easy to miss on a screen that's already playing.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSaved = true
            saveMessage = Strings.savedToPhotos
        } catch {
            print("[film] save to Photos failed: \(error)")
            saveMessage = Strings.saveFailed
        }
    }
}

// MARK: - Adjust

/// The three things the Adjust sheet changes, as one value so the sheet can
/// hold a copy of them.
struct FilmAdjustments: Equatable {
    var includeTitleCard = true
    var includeCaptions = true
    var fadeSeconds = 0.35
}

/// What goes into the render. Kept as a plain form — it's a settings sheet,
/// and dressing it up would only make it harder to scan.
///
/// It edits a draft. It used to bind straight to the film's own state, and
/// the film re-renders whenever that state changes — so every 0.05s notch of
/// the slider kicked off a fresh export behind the sheet, and Cancel had
/// nothing to cancel because every change had already happened. Now nothing
/// leaves the sheet until Apply.
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

// MARK: - Session cache

/// The last film made for each story in this launch, so opening the film
/// again with nothing changed shows it instead of exporting it again.
///
/// In memory only, and one entry per story: it is a way to skip a wait, not
/// a library. A newer film for the same story replaces — and deletes — the
/// older file. A hit is checked against the disk, because iOS may have
/// cleared the temporary directory since.
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
