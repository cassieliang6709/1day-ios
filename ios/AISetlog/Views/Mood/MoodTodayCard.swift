import SwiftUI

struct MoodTodayBadge: View {
    @Environment(MoodStore.self) private var moods
    @State private var dayTick = 0
    @State private var isChoosing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let _ = dayTick
        let mood = moods.today?.mood
        Button { isChoosing = true } label: {
            Group {
                if let mood {
                    Image(mood.imageName)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "face.dashed")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(OneDay.inkFaint)
                }
            }
            .frame(width: 22, height: 22)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.map { "\(Strings.moodSectionTitle): \($0.label)" } ?? Strings.moodSectionTitle)
        .accessibilityIdentifier("mood-today-badge")
        .sheet(isPresented: $isChoosing) { DailyCheckInSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in dayTick += 1 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { dayTick += 1 } }
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
