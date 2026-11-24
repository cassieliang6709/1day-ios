import SwiftUI

struct LibrarySection: View {
    let library: ClipLibrary
    let rooms: [Challenge]
    let onOpenStory: (UUID) -> Void
    var draftsRequest = 0
    @Binding var isSelecting: Bool
    @Binding var picked: [LibraryClip]

    enum Mode: Hashable { case grid, calendar }

    private static let inset: CGFloat = OneDay.Space.xl

    @State private var mode: Mode = .grid
    @State private var day: Date?
    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var activeDraft: ClipDraft?
    @State private var playing: LibraryClip?
    @State private var afterPlaying: (() -> Void)?
    @State private var sendDraft: ClipDraft?
    @State private var deleteDraft: ClipDraft?

    @Environment(MoodStore.self) private var moodStore: MoodStore?
    @Environment(ClipDraftStore.self) private var draftStore

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var cameraIndex: ClipCameraIndex { .shared }
    private var scope: ClipLibrary { library.scoped(includingFriends: false) }
    private var shown: [LibraryClip] {
        scope.filtered(.mine, cameras: cameraIndex.cameras, on: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !scope.clips.isEmpty {
                if mode == .calendar {
                    LibraryCalendar(
                        month: $month,
                        covers: scope.coverByDay(
                            scope.filtered(.mine, cameras: cameraIndex.cameras)),
                        selectedDay: $day,
                        showsMoods: true)
                        .padding(.horizontal, Self.inset)
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
                    .padding(.horizontal, Self.inset)
                }

                if mode == .grid || day != nil {
                    if !shown.isEmpty {
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
        .task(id: library.clips.map(\.cameraKey)) {
            cameraIndex.load(library.clips)
        }
    }



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
            .padding(.horizontal, Self.inset)
    }


    private var grid: some View {
        // One card per day: date, mood and count on top, that day's clips below, and a shortcut to make that day's vlog.
        LazyVStack(alignment: .leading, spacing: OneDay.Space.l) {
            ForEach(dayGroups, id: \.day) { group in
                GlassCard(padding: OneDay.Space.m) {
                    VStack(alignment: .leading, spacing: OneDay.Space.m) {
                        dayHeader(group.day, clips: group.clips)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: OneDay.Space.xs), count: 3),
                            spacing: OneDay.Space.xs
                        ) {
                            ForEach(group.clips) { clip in
                                cell(clip)
                            }
                        }
                    }
                }
                .padding(.horizontal, Self.inset)
            }
        }
    }

    private func play(from clip: LibraryClip) {
        playing = clip
    }

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

    private func dayHeader(_ day: Date, clips: [LibraryClip]) -> some View {
        HStack(alignment: .center, spacing: OneDay.Space.s) {
            Text(Calendar.current.isDateInToday(day) ? Strings.mineTodayHeader : dayTitle(day))
                .font(OneDay.Font.headline)
                .foregroundStyle(OneDay.ink)
            if let mood = moodStore?.mood(on: day)?.mood {
                Image(mood.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .accessibilityLabel(mood.label)
            }
            Spacer(minLength: 0)
            if isSelecting {
                let allPicked = clips.allSatisfy(picked.contains)
                Button(allPicked ? Strings.libraryDeselectDay : Strings.librarySelectDay) {
                    if allPicked {
                        picked.removeAll(where: clips.contains)
                    } else {
                        picked += clips.filter { !picked.contains($0) }.sorted { $0.recordedAt < $1.recordedAt }
                    }
                }
                    .font(OneDay.Font.caption)
                    .foregroundStyle(OneDay.brandText)
                    .padding(.horizontal, OneDay.Space.m)
                    .frame(minHeight: 32)
                    .background(Color.oneDayBrand.opacity(0.14), in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-day-select-all")
            }
        }
        .accessibilityElement(children: .contain)
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
            ClipTile(url: clip.url, refreshToken: clip.recordedAt, bedsInsteadOfCrops: true,
                     isSelected: order != nil)
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) { ClipTileLabel(text: Self.clockTime(clip.recordedAt)) }
                .overlay(alignment: .topTrailing) {
                    if isSelecting { pickMark(order) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(clip))
        .accessibilityAddTraits(order != nil ? .isSelected : [])
    }

    static func clockTime(_ date: Date) -> String {
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
        let place: String? = switch clip.source {
        case .story(_, let title, _): title
        case .draft: nil
        }
        return [who, place].compactMap { $0 }.joined(separator: " · ")
    }

    private func accessibility(_ clip: LibraryClip) -> String {
        "\(clip.recordedAt.formatted(date: .abbreviated, time: .shortened)), \(sourceLine(clip))"
    }
}

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

struct VlogRequest: Identifiable {
    let clips: [LibraryClip]
    var id: String { clips.map(\.id).joined(separator: "|") }
}


struct LibraryCalendar: View {
    @Binding var month: Date
    let covers: [Date: LibraryClip]
    @Binding var selectedDay: Date?
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
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
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

    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: lead) + days.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        var localized = calendar
        localized.locale = AppLanguage.effective.locale
        let symbols = localized.veryShortStandaloneWeekdaySymbols
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
