import SwiftUI

/// 我的's archive (1.5): every clip — yours, your friends', drafts — with a
/// camera filter row, a people menu, a grid or a month calendar, and a select mode that turns any
/// set of clips into a vlog. Lives inside `PlansHomeView`'s scroll view, which
/// keeps the header, the in-progress story card and all launch routing.
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

    @State private var filter: LibraryFilter = .all
    @State private var mode: Mode = .grid
    @State private var day: Date?
    @State private var month = Calendar.current.startOfMonth(for: .now)
    /// The draft whose 放进故事 / 删除 choice is up. See `draftActions`.
    @State private var activeDraft: ClipDraft?

    @Environment(MoodStore.self) private var moodStore: MoodStore?
    @Environment(ClipDraftStore.self) private var draftStore

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var cameraIndex: ClipCameraIndex { .shared }
    private var shown: [LibraryClip] {
        library.filtered(filter, cameras: cameraIndex.cameras, on: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleRow
            filterRow

            if library.clips.isEmpty {
                emptyLine(Strings.libraryEmpty)
            } else {
                if mode == .calendar {
                    LibraryCalendar(
                        month: $month,
                        covers: library.coverByDay(
                            library.filtered(filter, cameras: cameraIndex.cameras)),
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
        .draftActions(for: $activeDraft)
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

            if !library.clips.isEmpty {
                peopleMenu

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

    /// 全部人 / 我拍的 / 朋友拍的. A menu rather than chips: it is the less
    /// used of the two filters, and the chip row belongs to the cameras.
    private var peopleMenu: some View {
        Menu {
            Picker(Strings.filterWhoFilmed, selection: $filter.people) {
                ForEach(LibraryFilter.People.allCases, id: \.self) { people in
                    Text(peopleName(people)).tag(people)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(peopleName(filter.people))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
            }
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            .foregroundStyle(filter.people == .everyone ? OneDay.inkSoft : OneDay.brandText)
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(OneDay.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
        }
        .accessibilityLabel(Strings.filterWhoFilmed)
        .accessibilityValue(peopleName(filter.people))
        .accessibilityIdentifier("library-people")
    }

    private func peopleName(_ people: LibraryFilter.People) -> String {
        switch people {
        case .everyone: Strings.filterEveryone
        case .mine: Strings.filterMine
        case .friends: Strings.filterFriends
        }
    }

    /// 全部, 待归档 (N) when there are drafts, then one chip per camera that
    /// has at least one clip. With nothing but 全部 the row isn't drawn.
    @ViewBuilder
    private var filterRow: some View {
        let cameras = library.cameras(in: cameraIndex.cameras)
        let draftCount = library.draftCount
        if !cameras.isEmpty || draftCount > 0 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(Strings.filterAll, isOn: filter.camera == nil && !filter.draftsOnly) {
                        filter.camera = nil
                        filter.draftsOnly = false
                    }
                    .accessibilityIdentifier("library-filter-all")
                    if draftCount > 0 {
                        chip(Strings.libraryDraftsChip(draftCount), isOn: filter.draftsOnly) {
                            filter.camera = nil
                            filter.draftsOnly = true
                        }
                        .accessibilityIdentifier("library-filter-drafts")
                    }
                    ForEach(cameras) { style in
                        chip(style.displayName, isOn: filter.camera == style) {
                            filter.draftsOnly = false
                            filter.camera = style
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// 待归档 from the camera's drafts button: the grid, every date, drafts only.
    private func showDrafts() {
        isSelecting = false
        mode = .grid
        day = nil
        filter.camera = nil
        filter.draftsOnly = true
    }

    private func chip(_ label: String, isOn: Bool, select: @escaping () -> Void) -> some View {
        Button {
            withAnimation(OneDay.Motion.snap) { select() }
        } label: {
            Text(label)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .monospacedDigit()
                .foregroundStyle(isOn ? OneDay.onBrand : OneDay.inkSoft)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background {
                    if isOn {
                        Capsule().fill(Color.oneDayBrand)
                    } else {
                        Capsule().fill(OneDay.surface)
                            .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
    /// and how many clips it holds. Tiles are 9:16, the shape a phone films
    /// in, with 3pt gaps the way Photos packs a grid — a 3:4 card with a
    /// heavy caption read as a wall of boxes rather than a day of footage.
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
            } else if let story = clip.storyID {
                onOpenStory(story)
            } else if case .draft(let id) = clip.source {
                activeDraft = draftStore.sortedDrafts.first { $0.id == id }
            }
        } label: {
            // A fixed 3:4 box with the thumbnail cropped into it: given the
            // thumbnail itself as the sizing view, a portrait clip grew the
            // cell past its column and over the filter row.
            Color.clear
                .aspectRatio(9 / 16, contentMode: .fit)
                .overlay { ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt) }
                .clipped()
                .overlay(alignment: .bottomLeading) { caption(clip) }
                .overlay(alignment: .bottomTrailing) {
                    if clip.storyID == nil { draftBadge }
                }
                .overlay(alignment: .topLeading) {
                    // Only someone else's clip says whose it is; yours don't
                    // need a face on every tile.
                    if !clip.isMine {
                        AvatarDot(name: clip.authorName, size: 20)
                            .padding(6)
                    }
                }
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

    private var draftBadge: some View {
        Text(Strings.libraryDraftBadge)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(5)
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
