import SwiftUI

/// 我的's archive (1.5): your clips — from every story and room, plus your
/// drafts — as a grid or a month calendar, and a select mode that turns any
/// set of clips into a vlog. Lives inside `PlansHomeView`'s scroll view,
/// which keeps the header, the in-progress story card and all launch routing.
///
/// Only ever yours. Friends' clips stay in the room they were filmed in: 我的
/// is *my* area, and finding a friend's clip in it read as "did I film this?".
/// There is no filter row any more either — no 含朋友的, no 只有我, no camera
/// chips (there is one camera) — so everything the page computes goes
/// through `scope`, and no number on the page counts a clip the grid hides.
struct LibrarySection: View {
    let library: ClipLibrary
    /// Shared stories. No longer drawn as chips (the row filters by camera
    /// now); kept so the page's call site doesn't change.
    let rooms: [Challenge]
    let onOpenStory: (UUID) -> Void
    /// Bumped by the camera's drafts button (via the shell): show 待归档.
    var draftsRequest = 0
    /// Owned by the page, which floats the 生成 vlog bar over its scroll view
    /// and presents the sheet. See `LibrarySelectionBar`.
    @Binding var isSelecting: Bool
    @Binding var picked: [LibraryClip]

    enum Mode: Hashable { case grid, calendar }

    @State private var mode: Mode = .grid
    @State private var day: Date?
    @State private var month = Calendar.current.startOfMonth(for: .now)
    /// The draft whose 放进故事 / 删除 choice is up. See `draftActions`.
    @State private var activeDraft: ClipDraft?
    /// The clip open full screen after a tap on it.
    @State private var playing: LibraryClip?
    /// What the player asked for, run once its sheet is gone: a second sheet
    /// can't come up while the first is still on screen.
    @State private var afterPlaying: (() -> Void)?
    @State private var sendDraft: ClipDraft?
    @State private var deleteDraft: ClipDraft?

    @Environment(MoodStore.self) private var moodStore: MoodStore?
    @Environment(ClipDraftStore.self) private var draftStore

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var cameraIndex: ClipCameraIndex { .shared }
    /// The library this page draws from: my clips, never a friend's.
    private var scope: ClipLibrary { library.scoped(includingFriends: false) }
    private var shown: [LibraryClip] {
        scope.filtered(.mine, cameras: cameraIndex.cameras, on: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleRow

            if scope.clips.isEmpty {
                emptyLine(Strings.libraryEmpty)
            } else {
                if mode == .calendar {
                    LibraryCalendar(
                        month: $month,
                        covers: scope.coverByDay(
                            scope.filtered(.mine, cameras: cameraIndex.cameras)),
                        selectedDay: $day,
                        showsMoods: true)
                        .padding(.horizontal, 20)
                }

                if let day {
                    Button {
                        self.day = nil
                    } label: {
                        Label(
                            "\(day.formatted(.dateTime.month().day())) · \(Strings.libraryAllDays)",
                            systemImage: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(OneDay.brandText)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }

                if mode == .grid || day != nil {
                    if shown.isEmpty {
                        emptyLine(Strings.libraryNothingHere)
                    } else {
                        grid
                    }
                }
            }
        }
        .onChange(of: isSelecting) { _, selecting in
            if !selecting { picked = [] }
        }
        .onChange(of: draftsRequest) { _, _ in showDrafts() }
        .draftActions(for: $activeDraft, send: $sendDraft, delete: $deleteDraft)
        .fullScreenCover(item: $playing, onDismiss: {
            afterPlaying?()
            afterPlaying = nil
        }) { clip in
            LibraryClipEditor(
                clip: clip,
                draft: draft(for: clip),
                onOpenStory: { id in finishPlaying { onOpenStory(id) } },
                onSend: { draft in finishPlaying { sendDraft = draft } },
                onDelete: { draft in finishPlaying { deleteDraft = draft } })
        }
        // Reads each clip's camera off the main actor, once; cached app-wide.
        .task(id: library.clips.map(\.cameraKey)) {
            cameraIndex.load(library.clips)
        }
    }

    // MARK: - Header

    private var titleRow: some View {
        HStack(spacing: 10) {
            SectionLabel(text: Strings.libraryTitle)
            Spacer(minLength: 6)

            if !scope.clips.isEmpty {
                Button {
                    withAnimation(OneDay.Motion.snap) {
                        mode = mode == .grid ? .calendar : .grid
                        if mode == .grid { day = nil }
                    }
                } label: {
                    Image(systemName: mode == .grid ? "calendar" : "square.grid.3x3")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(OneDay.ink)
                        .frame(width: 38, height: 38)
                        .background(OneDay.surface, in: Circle())
                        .overlay(Circle().strokeBorder(OneDay.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode == .grid ? Strings.libraryCalendar : Strings.libraryGrid)
                .accessibilityIdentifier("library-mode")

                Button(isSelecting ? Strings.cancel : Strings.librarySelect) {
                    withAnimation(OneDay.Motion.snap) { isSelecting.toggle() }
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.brandText)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.oneDayBrand.opacity(0.1), in: Capsule())
                .accessibilityIdentifier("library-select")
            }
        }
        .padding(.horizontal, 20)
    }

    /// The camera's drafts button: the grid, every date. It used to narrow
    /// to 只有我 (drafts only); that chip is gone, so this shows everything.
    private func showDrafts() {
        isSelecting = false
        mode = .grid
        day = nil
    }


    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(OneDay.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
    }

    // MARK: - Grid

    /// A diary: one block per day, newest day first, each headed by its date
    /// and how many clips it holds. Tiles are 3:4, the shape of the DV and
    /// instant cameras, with 3pt gaps the way Photos packs a grid. The whole
    /// frame shows — border, date and all — since that is what tells the
    /// cameras apart; a 2:3 film clip sits in its tile on a blurred bed.
    private var grid: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(dayGroups, id: \.day) { group in
                VStack(alignment: .leading, spacing: 9) {
                    dayHeader(group.day, count: group.clips.count)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                        spacing: 3
                    ) {
                        ForEach(group.clips) { clip in
                            cell(clip)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    /// The tapped clip, on its own, full screen. It used to play the clip's
    /// whole day in a row; what people tapped a clip for was that clip.
    private func play(from clip: LibraryClip) {
        playing = clip
    }

    /// The `ClipDraft` behind a clip in no story.
    private func draft(for clip: LibraryClip) -> ClipDraft? {
        guard case .draft(let id) = clip.source else { return nil }
        return draftStore.sortedDrafts.first { $0.id == id }
    }

    private func finishPlaying(_ next: @escaping () -> Void) {
        afterPlaying = next
        playing = nil
    }

    private var dayGroups: [(day: Date, clips: [LibraryClip])] {
        let calendar = Calendar.current
        return Dictionary(grouping: shown) { calendar.startOfDay(for: $0.recordedAt) }
            .map { (day: $0.key, clips: $0.value.sorted { $0.recordedAt > $1.recordedAt }) }
            .sorted { $0.day > $1.day }
    }

    /// 「10月16日 周四 😀 · 3 段」: the date, that day's mood face if one was
    /// picked, and how many clips the day holds.
    private func dayHeader(_ day: Date, count: Int) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(dayTitle(day))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
            if let mood = moodStore?.mood(on: day)?.mood {
                Image(mood.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .accessibilityLabel(mood.label)
            }
            Text("· \(Strings.libraryClipCount(count))")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.inkFaint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private func dayTitle(_ day: Date) -> String {
        day.formatted(
            .dateTime.month().day().weekday(.abbreviated)
                .locale(AppLanguage.effective.locale))
    }

    private func cell(_ clip: LibraryClip) -> some View {
        let order = picked.firstIndex(of: clip)
        return Button {
            if isSelecting {
                if let order { picked.remove(at: order) } else { picked.append(clip) }
            } else {
                play(from: clip)
            }
        } label: {
            // A fixed 3:4 box with the thumbnail fitted into it: given the
            // thumbnail itself as the sizing view, a portrait clip grew the
            // cell past its column and over the row above.
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt, bedsInsteadOfCrops: true)
                }
                .clipped()
                .overlay(alignment: .bottomLeading) { caption(clip) }
                .overlay(alignment: .topTrailing) {
                    if isSelecting { pickMark(order) }
                }
                .overlay {
                    if order != nil {
                        Rectangle().strokeBorder(Color.oneDayBrand, lineWidth: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(clip))
        .accessibilityAddTraits(order != nil ? .isSelected : [])
    }

    /// Just the time, small. Where the clip lives is in the accessibility
    /// label and one tap away; on the tile it was a second line of text on
    /// every picture.
    private func caption(_ clip: LibraryClip) -> some View {
        Text(clockTime(clip.recordedAt))
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            .padding(6)
    }

    /// 24-hour 「17:05」. `.dateTime.hour(.twoDigits(amPM: .omitted)).minute()`
    /// gave 「05:0」 for 5:00 pm: twelve-hour, and the minute unpadded.
    private func clockTime(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func pickMark(_ order: Int?) -> some View {
        ZStack {
            Circle()
                .fill(order != nil ? Color.oneDayBrand : .black.opacity(0.25))
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            if let order {
                Text("\(order + 1)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .padding(6)
    }

    private func sourceLine(_ clip: LibraryClip) -> String {
        let who = clip.isMine ? nil : clip.authorName
        let place: String = switch clip.source {
        case .story(_, let title, _): title
        case .draft: Strings.libraryUnfiled
        }
        return [who, place].compactMap { $0 }.joined(separator: " · ")
    }

    private func accessibility(_ clip: LibraryClip) -> String {
        "\(clip.recordedAt.formatted(date: .abbreviated, time: .shortened)), \(sourceLine(clip))"
    }
}

/// Floats above the tab bar while picking clips: how many, roughly how long,
/// and the button that opens the arrange sheet.
struct LibrarySelectionBar: View {
    let picked: [LibraryClip]
    let onMake: () -> Void

    @State private var seconds: Int?

    var body: some View {
        HStack(spacing: 12) {
            Text(picked.isEmpty
                 ? Strings.pickClipsHint
                 : Strings.librarySelectedSummary(picked.count, seconds: seconds))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OneDay.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("library-selected-summary")
            Spacer(minLength: 4)
            Button(Strings.libraryMakeVlogCTA, action: onMake)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.onBrand)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Color.oneDayBrand, in: Capsule())
                .opacity(picked.isEmpty ? 0.45 : 1)
                .disabled(picked.isEmpty)
                .accessibilityIdentifier("library-make-vlog")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassSurface(radius: 30)
        .padding(.horizontal, 20)
        .task(id: picked.map(\.id)) {
            seconds = nil
            seconds = await ClipDurations.totalSeconds(of: picked.map(\.url))
        }
    }
}

/// Wraps the picked clips so `.sheet(item:)` can present them.
struct VlogRequest: Identifiable {
    let clips: [LibraryClip]
    var id: String { clips.map(\.id).joined(separator: "|") }
}

// MARK: - Calendar

/// One month, Monday- or Sunday-first per the locale. A day with clips shows
/// its first clip; tapping it narrows the grid below to that day.
struct LibraryCalendar: View {
    @Binding var month: Date
    let covers: [Date: LibraryClip]
    @Binding var selectedDay: Date?
    /// 我的 shows each day's mood face in place of the clip dot. Room
    /// calendars leave it off: a mood is private to its owner.
    var showsMoods = false

    @Environment(MoodStore.self) private var moodStore: MoodStore?
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.year().month(.wide)))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OneDay.inkSoft)
            .buttonStyle(.plain)
            .frame(minHeight: 44)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 52) }
                }
            }
        }
        .padding(12)
        .glassSurface(radius: OneDay.Radius.card)
    }

    /// A number, and under it a small round frame of that day's first clip.
    /// The selected day gets a filled circle. A thumbnail stretched over the
    /// whole cell made one busy day the loudest thing in the month and every
    /// row three times taller than its numbers needed.
    private func dayCell(_ date: Date) -> some View {
        let cover = covers[calendar.startOfDay(for: date)]
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isToday = calendar.isDateInToday(date)
        return Button {
            guard cover != nil else { return }
            selectedDay = isSelected ? nil : date
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday || cover != nil ? .heavy : .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        isSelected ? OneDay.onBrand
                            : isToday ? OneDay.brandText
                            : cover != nil ? OneDay.ink : OneDay.inkFaint)
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected { Circle().fill(Color.oneDayBrand) }
                    }
                dayMark(cover: cover, mood: mood(on: date))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cover == nil)
    }

    private func mood(on date: Date) -> Mood? {
        guard showsMoods else { return nil }
        return moodStore?.mood(on: date)?.mood
    }

    /// The mood face if the day has one, else the first clip as a small dot.
    @ViewBuilder
    private func dayMark(cover: LibraryClip?, mood: Mood?) -> some View {
        if let mood {
            Image(mood.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
                .accessibilityLabel(mood.label)
        } else if let cover {
            Color.clear
                .overlay { ClipThumbnail(url: cover.url, refreshToken: cover.recordedAt) }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .frame(width: 14, height: 14)
                .frame(height: 19)
        } else {
            Color.clear.frame(width: 14, height: 19)
        }
    }

    /// Leading blanks, then each day of the month.
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: lead) + days.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) {
            withAnimation(OneDay.Motion.snap) { month = next }
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}

// MARK: - One clip

/// A clip from 我的, in the same full-screen editor a room opens: the video
/// edge to edge, its captions on it, and what to do with it underneath — send
/// a clip only you can see to a story, or open the story a clip is already in.
/// Deleting a draft sits in the ⋯ menu.
struct LibraryClipEditor: View {
    let clip: LibraryClip
    let draft: ClipDraft?
    let onOpenStory: (UUID) -> Void
    let onSend: (ClipDraft) -> Void
    let onDelete: (ClipDraft) -> Void

    @Environment(ClipDraftStore.self) private var draftStore

    var body: some View {
        switch clip.source {
        case .story(let id, _, _):
            ClipPreviewView(
                day: clip.clip.day,
                slotTitle: clip.clip.label,
                authorName: clip.authorName,
                captions: clip.clip.captions,
                showsPrompt: clip.clip.label != nil,
                url: clip.url,
                recordedAt: clip.recordedAt,
                challengeID: id,
                targetAuthorID: clip.clip.authorID,
                takeID: clip.clip.takeID,
                onReRecord: nil,
                extraActions: [.init(
                    id: "library-day-open-story", symbol: "rectangle.stack",
                    title: Strings.libraryOpenStory) { onOpenStory(id) }])
        case .draft(let id):
            ClipPreviewView(
                day: 1,
                captions: draft?.captions ?? clip.clip.captions,
                showsPrompt: false,
                url: clip.url,
                recordedAt: clip.recordedAt,
                onReRecord: nil,
                onDraftCaptions: { draftStore.updateCaptions($0, draftID: id) },
                extraActions: draftActions)
        }
    }

    private var draftActions: [ClipPreviewView.ExtraAction] {
        guard let draft else { return [] }
        return [
            .init(
                id: "library-day-send", symbol: "tray.and.arrow.down",
                title: Strings.libraryFileIntoStory) { onSend(draft) },
            .init(
                id: "library-day-delete", symbol: "trash",
                title: Strings.deleteDraft, isDestructive: true) { onDelete(draft) },
        ]
    }
}
