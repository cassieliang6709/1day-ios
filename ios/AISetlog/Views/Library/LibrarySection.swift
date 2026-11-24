import SwiftUI

struct LibrarySection: View {
    let library: ClipLibrary
    let rooms: [Challenge]
    let onOpenStory: (UUID) -> Void
    var draftsRequest = 0
    @Binding var isSelecting: Bool
    @Binding var picked: [LibraryClip]
    var onFilmToday: (() -> Void)? = nil

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
        LazyVStack(alignment: .leading, spacing: OneDay.Space.xxl) {
            ForEach(dayGroups, id: \.day) { group in
                VStack(alignment: .leading, spacing: OneDay.Space.s) {
                    dayHeader(group.day, clips: group.clips)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: OneDay.Space.xs), count: 3),
                        spacing: OneDay.Space.xs
                    ) {
                        ForEach(group.clips) { clip in
                            cell(clip)
                        }
                        if group.clips.isEmpty, let onFilmToday, !isSelecting {
                            filmTodayTile(onFilmToday)
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
        var groups = Dictionary(grouping: shown) { calendar.startOfDay(for: $0.recordedAt) }
            .map { (day: $0.key, clips: $0.value.sorted { $0.recordedAt < $1.recordedAt }) }
            .sorted { $0.day > $1.day }
        if day == nil, onFilmToday != nil, !groups.contains(where: { calendar.isDateInToday($0.day) }) {
            groups.insert((day: calendar.startOfDay(for: .now), clips: []), at: 0)
        }
        return groups
    }

    private func filmTodayTile(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: OneDay.Radius.tile, style: .continuous)
                .fill(Color.oneDayBrand.opacity(0.18))
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    VStack(spacing: OneDay.Space.xs) {
                        Image(systemName: "camera.fill")
                            .font(OneDay.Font.headline)
                        Text(Strings.libraryFilmToday)
                            .font(OneDay.Font.caption)
                    }
                    .foregroundStyle(OneDay.brandText)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-film-today")
    }

    private func dayHeader(_ day: Date, clips: [LibraryClip]) -> some View {
        HStack(alignment: .center, spacing: OneDay.Space.s) {
            Text(Calendar.current.isDateInToday(day) ? Strings.mineTodayHeader : dayTitle(day))
                .font(OneDay.Font.headline)
                .foregroundStyle(OneDay.ink)
            if Calendar.current.isDateInToday(day) {
                MoodTodayBadge()
            } else if let mood = moodStore?.mood(on: day)?.mood {
                Image(mood.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .accessibilityLabel(mood.label)
            }
            Spacer(minLength: 0)
            if isSelecting, !clips.isEmpty {
                let allPicked = clips.allSatisfy(picked.contains)
                Button(allPicked ? Strings.libraryDeselectDay : Strings.librarySelectDay) {
                    if allPicked {
                        picked.removeAll(where: clips.contains)
                    } else {
                        picked += clips.filter { !picked.contains($0) }.sorted { $0.recordedAt < $1.recordedAt }
                    }
                }
                    .font(OneDay.Font.callout)
                    .foregroundStyle(OneDay.brandText)
                    .frame(minHeight: 44)
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
