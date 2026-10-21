import SwiftUI

/// 我的 → 今天的心情: five faces, tap one, that's today's (1.5). Tap
/// another to change it. No line to write any more, and no 记下了 — the
/// picked face standing out is what saved looks like.
///
/// `compact` is the half-width card beside 今天的计划: the faces sit three
/// and two, without their names.
struct MoodTodayCard: View {
    var compact = false

    @Environment(MoodStore.self) private var moods
    /// Bumped when the date rolls over or the app comes back, so a card left
    /// on screen overnight shows today (empty) rather than yesterday's mood.
    @State private var dayTick = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let _ = dayTick
        GlassCard(padding: compact ? 14 : 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(Strings.moodSectionTitle)
                    .font(OneDay.Font.callout)
                    .foregroundStyle(OneDay.ink)
                MoodFaceRow(selected: moods.today?.mood, compact: compact) { moods.setMood($0) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mood-today-card")
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in dayTick += 1 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { dayTick += 1 } }
    }
}

private struct MoodFaceRow: View {
    let selected: Mood?
    let compact: Bool
    let onPick: (Mood) -> Void

    var body: some View {
        if compact {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 6) {
                faces
            }
        } else {
            HStack(spacing: 4) { faces }
        }
    }

    private var faces: some View {
        ForEach(Mood.allCases) { mood in
            MoodFaceButton(mood: mood, state: state(for: mood), showsLabel: !compact) { onPick(mood) }
        }
    }

    private func state(for mood: Mood) -> MoodFaceButton.State {
        guard let selected else { return .idle }
        return selected == mood ? .selected : .dimmed
    }
}

struct MoodFaceButton: View {
    enum State { case idle, selected, dimmed }

    let mood: Mood
    let state: State
    var showsLabel = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                face
                if showsLabel {
                    Text(mood.label)
                        .font(OneDay.Font.micro)
                        .foregroundStyle(state == .selected ? OneDay.brandText : OneDay.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(state == .dimmed ? 0.45 : 1)
        .zIndex(state == .selected ? 1 : 0)
        .animation(.spring(duration: 0.25), value: state)
        .accessibilityLabel(mood.label)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
        .accessibilityIdentifier("mood-\(mood.rawValue)")
    }

    private var face: some View {
        Image(mood.imageName)
            .resizable()
            .scaledToFit()
            .frame(width: showsLabel ? 50 : 38, height: showsLabel ? 50 : 38)
            .padding(4)
            .background(Circle().fill(Color.oneDayBrand.opacity(state == .selected ? 0.18 : 0)))
            // Picked: clearly bigger than the rest, which fade. Drawn over
            // its neighbours (see `zIndex` on the button), since scaling
            // doesn't make room in the row.
            .scaleEffect(state == .selected ? 1.4 : 1)
    }
}
