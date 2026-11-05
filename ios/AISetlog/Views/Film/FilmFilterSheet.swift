import SwiftUI
import AVFoundation

/// What the film page asked the filter sheet to open on: everyone, or one
/// person's takes straight away.
struct FilmFilterTarget: Identifiable {
    /// `FilmPerson.id`, or nil for the list of everyone.
    let person: String?
    var id: String { person ?? "" }
}

// MARK: - The row on the film page

/// Everyone in the room's film as a row of faces, under the player.
///
/// Tapping a face goes straight to that person's takes; 筛选 opens the list of
/// everyone. Someone left out is drawn faded, so the row says who's in the
/// film you're watching without opening anything.
struct FilmPeopleRow: View {
    let people: [FilmPerson]
    let selection: FilmSelection
    let onOpen: (FilmFilterTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // No 成片里有谁 title: the faces already say it.
            HStack {
                Spacer()
                Button {
                    onOpen(FilmFilterTarget(person: nil))
                } label: {
                    Label(Strings.filmFilter, systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.brandText)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("film-filter")
            }

            // Six people at 64pt is wider than a phone, so the row scrolls
            // rather than shrinking faces until they can't be told apart.
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        Button {
                            onOpen(FilmFilterTarget(person: person.id))
                        } label: {
                            FilmPersonBadge(person: person, selection: selection, size: 46)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("film-person-\(index)")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .glassSurface(radius: OneDay.Radius.card)
    }
}

/// One face, their name, and how many of their takes are in.
private struct FilmPersonBadge: View {
    let person: FilmPerson
    let selection: FilmSelection
    var size: CGFloat = 46

    private var included: Bool { selection.includes(person: person.id) }
    private var keptCount: Int { person.clips.filter(selection.includes).count }
    private var heldCount: Int {
        person.clips.filter { selection.includes($0) && selection.freeze(of: $0.id) != nil }.count
    }

    var body: some View {
        VStack(spacing: 4) {
            MemberFace(id: person.id, name: person.name, size: size, showsMood: false)
                .opacity(included ? 1 : 0.32)
                .overlay(alignment: .bottomTrailing) {
                    if included, heldCount > 0 {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: size * 0.34))
                            .foregroundStyle(.white, Color.oneDayLavender)
                            .offset(x: 3, y: 3)
                    }
                }
            Text(person.name ?? Strings.defaultMemberName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(included ? OneDay.ink : OneDay.inkFaint)
                .lineLimit(1)
            Text(included
                ? Strings.filmClipsKept(keptCount, of: person.clips.count)
                : Strings.filmLeftOut)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OneDay.inkFaint)
        }
        .frame(width: max(size + 18, 64))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The sheet

/// Whose takes go in, which ones, and which stand still.
///
/// Edits a draft, like `AdjustFilmSheet` and for the same reason: the film
/// re-renders whenever the selection changes, so nothing leaves the sheet
/// until Apply.
struct FilmFilterSheet: View {
    let people: [FilmPerson]
    let onApply: (FilmSelection) -> Void

    @State private var draft: FilmSelection
    @State private var path: [String]
    @Environment(\.dismiss) private var dismiss

    init(
        people: [FilmPerson],
        selection: FilmSelection,
        target: FilmFilterTarget,
        onApply: @escaping (FilmSelection) -> Void
    ) {
        self.people = people
        self.onApply = onApply
        _draft = State(initialValue: selection)
        _path = State(initialValue: target.person.map { [$0] } ?? [])
    }

    private var allClips: [DayClip] { people.flatMap(\.clips) }
    private var leavesNothing: Bool { !allClips.contains(where: draft.includes) }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                                Button {
                                    draft.set(
                                        person: person.id,
                                        included: !draft.includes(person: person.id))
                                } label: {
                                    FilmPersonBadge(person: person, selection: draft, size: 52)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: draft.includes(person: person.id)
                                                ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(draft.includes(person: person.id)
                                                    ? Color.oneDayBrand : OneDay.inkFaint)
                                                .background(Circle().fill(.white))
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("film-filter-toggle-\(index)")
                                .accessibilityAddTraits(
                                    draft.includes(person: person.id) ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)
                } header: {
                    Text(Strings.filmPeopleHeader)
                }

                Section(Strings.filmPerPersonHeader) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        NavigationLink(value: person.id) {
                            HStack(spacing: 12) {
                                MemberFace(id: person.id, name: person.name, size: 30, showsMood: false)
                                    .opacity(draft.includes(person: person.id) ? 1 : 0.32)
                                Text(person.name ?? Strings.defaultMemberName)
                                    .font(.body.weight(.semibold))
                                Spacer()
                                Text(summary(for: person))
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("film-filter-person-\(index)")
                    }
                }

                // 排顺序 (1.5): which moment plays first. Your copy only.
                if Set(allClips.filter(draft.includes).map(\.day)).count > 1 {
                    Section {
                        NavigationLink(value: FilmOrderPage.route) {
                            Label(Strings.filmOrder, systemImage: "arrow.up.arrow.down")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityIdentifier("film-order")
                    }
                }

                if leavesNothing {
                    Section {
                        Text(Strings.filmNothingLeft)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .tint(Color.oneDayBrand)
            .navigationTitle(Strings.filmFilter)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { key in
                if key == FilmOrderPage.route {
                    FilmOrderPage(clips: allClips.filter(draft.includes), draft: $draft)
                } else if let person = people.first(where: { $0.id == key }) {
                    FilmPersonPage(person: person, draft: $draft)
                }
            }
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
                    .disabled(leavesNothing)
                    .accessibilityIdentifier("film-filter-apply")
                }
            }
        }
    }

    private func summary(for person: FilmPerson) -> String {
        guard draft.includes(person: person.id) else { return Strings.filmLeftOut }
        let kept = person.clips.filter(draft.includes)
        let held = kept.filter { draft.freeze(of: $0.id) != nil }.count
        let count = Strings.filmClipsKept(kept.count, of: person.clips.count)
        return held > 0 ? "\(count) · \(Strings.filmClipsHeld(held))" : count
    }
}

// MARK: - One person

/// One person's takes: in or out, one by one, and which of them stand still.
private struct FilmPersonPage: View {
    let person: FilmPerson
    @Binding var draft: FilmSelection

    private var included: Bool { draft.includes(person: person.id) }

    private var allHeld: Binding<Bool> {
        Binding {
            let kept = person.clips.filter(draft.includes)
            return !kept.isEmpty && kept.allSatisfy { draft.freeze(of: $0.id) != nil }
        } set: { hold in
            for clip in person.clips where draft.includes(clip) {
                if hold {
                    // Keep a frame already picked; a new hold starts on frame one.
                    if draft.freeze(of: clip.id) == nil { draft.set(freeze: 0, for: clip.id) }
                } else {
                    draft.set(freeze: nil, for: clip.id)
                }
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(Strings.filmPersonIncluded, isOn: Binding(
                    get: { included },
                    set: { draft.set(person: person.id, included: $0) }))
                    .accessibilityIdentifier("film-person-include")
                Toggle(Strings.filmPersonAllHeld, isOn: allHeld)
                    .disabled(!included)
                    .accessibilityIdentifier("film-person-hold-all")
            }

            Section(Strings.filmEachClip) {
                ForEach(Array(person.clips.enumerated()), id: \.element.id) { index, clip in
                    FilmClipPickRow(clip: clip, index: index, draft: $draft)
                        .disabled(!included)
                        .opacity(included ? 1 : 0.45)
                }
            }
        }
        .tint(Color.oneDayBrand)
        .navigationTitle(person.name ?? Strings.defaultMemberName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One take: its picture and time, whether it's in, and where it stops.
private struct FilmClipPickRow: View {
    let clip: DayClip
    let index: Int
    @Binding var draft: FilmSelection

    /// Loaded from the file; the slider waits for it.
    @State private var duration: Double?

    private var inFilm: Binding<Bool> {
        Binding(
            get: { !draft.leftOutClips.contains(clip.id) },
            set: { draft.set(clip: clip.id, included: $0) })
    }

    private var held: Binding<Bool> {
        Binding(
            get: { draft.freeze(of: clip.id) != nil },
            set: { draft.set(freeze: $0 ? 0 : nil, for: clip.id) })
    }

    private var heldAt: Double { draft.freeze(of: clip.id) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ClipThumbnail(url: clip.url)
                    .frame(width: 48, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(timeLabel)
                    .font(.body.weight(.semibold).monospacedDigit())
                Spacer()
                Toggle(Strings.filmClipInFilm, isOn: inFilm)
                    .labelsHidden()
                    .accessibilityLabel(Text("\(Strings.filmClipInFilm) \(timeLabel)"))
                    .accessibilityIdentifier("film-clip-include-\(index)")
            }

            if inFilm.wrappedValue {
                Toggle(Strings.filmHold, isOn: held)
                    .accessibilityIdentifier("film-clip-hold-\(index)")

                if held.wrappedValue {
                    HStack(alignment: .top, spacing: 12) {
                        FrameThumbnail(url: clip.url, seconds: heldAt)
                            .frame(width: 72, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Strings.filmHeldAt(heldAt))
                                .font(.footnote.weight(.semibold).monospacedDigit())
                            if let duration, duration > 0 {
                                Slider(
                                    value: Binding(
                                        get: { min(heldAt, duration) },
                                        set: { draft.set(freeze: $0, for: clip.id) }),
                                    in: 0...duration)
                                    .accessibilityIdentifier("film-clip-hold-frame-\(index)")
                            } else {
                                ProgressView().controlSize(.small)
                            }
                            Text(Strings.filmHoldDragHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: clip.url) {
            let seconds = (try? await AVURLAsset(url: clip.url).load(.duration))
                .map(CMTimeGetSeconds) ?? 0
            // Stop one frame short, so the end of the slider is a frame there is.
            duration = seconds.isFinite ? max(seconds - 1.0 / 30, 0) : 0
        }
    }

    private var timeLabel: String {
        guard let recordedAt = clip.recordedAt else { return Strings.filmClipNumber(index + 1) }
        return recordedAt.formatted(
            Date.FormatStyle()
                .month(.defaultDigits).day()
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                .locale(AppLanguage.effective.resolved.locale))
    }
}

/// One exact frame of a take, for showing where a hold stops.
private struct FrameThumbnail: View {
    let url: URL
    let seconds: Double

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.systemGray5)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        // Rounded so a drag doesn't ask for a new frame on every point of it.
        .task(id: (seconds * 10).rounded()) {
            // Lets a fast drag settle before decoding a frame.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 300, height: 300)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image, !Task.isCancelled {
                image = UIImage(cgImage: cgImage)
            }
        }
    }
}

// MARK: - Order

/// 排顺序: the film's moments, one row each with everyone's take in it,
/// dragged into the order the film plays them. Kept on this phone with the
/// rest of the selection.
struct FilmOrderPage: View {
    static let route = "__film-order"

    let clips: [DayClip]
    @Binding var draft: FilmSelection

    private var days: [Int] { draft.orderedDays(clips.map(\.day)) }

    var body: some View {
        List {
            ForEach(days, id: \.self) { day in
                HStack(spacing: 6) {
                    ForEach(clips.filter { $0.day == day }) { clip in
                        ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt)
                            .frame(width: 42, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Strings.filmClipNumber((days.firstIndex(of: day) ?? 0) + 1))
                .accessibilityIdentifier("film-order-row")
            }
            .onMove { from, to in
                var order = days
                order.move(fromOffsets: from, toOffset: to)
                draft.dayOrder = order
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(Strings.filmOrder)
        .navigationBarTitleDisplayMode(.inline)
    }
}
