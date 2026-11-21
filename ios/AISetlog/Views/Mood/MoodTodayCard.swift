import SwiftUI

struct MoodTodayCard: View {
    var compact = false

    @Environment(MoodStore.self) private var moods
    @State private var dayTick = 0
    @State private var isChoosing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let _ = dayTick
        GlassCard(padding: compact ? 14 : 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(Strings.moodSectionTitle)
                    .font(OneDay.Font.callout)
                    .foregroundStyle(OneDay.ink)
                Group {
                    if let mood = moods.today?.mood, !isChoosing {
                        selectedMood(mood)
                    } else {
                        MoodFaceRow(selected: moods.today?.mood, compact: compact) {
                            moods.setMood($0)
                            isChoosing = false
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .animation(OneDay.Motion.soft, value: isChoosing)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mood-today-card")
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in dayTick += 1 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { dayTick += 1 } }
    }

    private func selectedMood(_ mood: Mood) -> some View {
        Button {
            isChoosing = true
        } label: {
            VStack(spacing: 6) {
                Image(mood.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                Text(mood.label)
                    .font(OneDay.Font.callout)
                    .foregroundStyle(OneDay.ink)
                Text(Strings.moodEditFaceHint)
                    .font(OneDay.Font.micro)
                    .foregroundStyle(OneDay.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.label)
        .accessibilityHint(Strings.moodEditFaceHint)
        .accessibilityIdentifier("mood-today-selected")
    }
}

/// 首页右上角的小心情入口：选过显示表情 + 名字，没选显示「今天的心情」，点开弹出 5 个表情。
struct MoodTodayBadge: View {
    @Environment(MoodStore.self) private var moods
    @State private var dayTick = 0
    @State private var isChoosing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let _ = dayTick
        let mood = moods.today?.mood
        Button { isChoosing = true } label: {
            HStack(spacing: OneDay.Space.xs) {
                // 固定尺寸：小图标，同一处只用这一档
                if let mood {
                    Image(mood.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: "face.smiling")
                        .font(OneDay.Font.rounded(.callout, weight: .semibold))
                        .foregroundStyle(OneDay.brandText)
                }
                Text(mood?.label ?? Strings.moodSectionTitle)
                    .font(OneDay.Font.caption)
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.leading, mood == nil ? OneDay.Space.m : OneDay.Space.xs)
            .padding(.trailing, OneDay.Space.m)
            .padding(.vertical, OneDay.Space.xs)
            .frame(minHeight: 36)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(OneDay.ink.opacity(0.08), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.map { "\(Strings.moodSectionTitle): \($0.label)" } ?? Strings.moodSectionTitle)
        .accessibilityIdentifier("mood-today-badge")
        .popover(isPresented: $isChoosing, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: OneDay.Space.m) {
                Text(Strings.moodPrompt)
                    .font(OneDay.Font.callout)
                    .foregroundStyle(OneDay.ink)
                MoodFaceRow(selected: mood, compact: false) {
                    moods.setMood($0)
                    isChoosing = false
                }
            }
            .padding(OneDay.Space.l)
            .frame(width: 320)
            .presentationCompactAdaptation(.popover)
        }
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
        .opacity(state == .dimmed ? 0.65 : 1)
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
            .background(Circle().fill(Color.oneDayBrand.opacity(state == .selected ? 0.12 : 0)))
            .overlay {
                Circle()
                    .strokeBorder(Color.oneDayBrand.opacity(state == .selected ? 0.8 : 0), lineWidth: 1.5)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(OneDay.brandText)
                    .frame(width: 16, height: 16)
                    .background(Color.oneDayBrand, in: Circle())
                    .overlay(Circle().strokeBorder(OneDay.surface, lineWidth: 2))
                    .opacity(state == .selected ? 1 : 0)
            }
            .scaleEffect(state == .selected ? 1.16 : 1)
    }
}
