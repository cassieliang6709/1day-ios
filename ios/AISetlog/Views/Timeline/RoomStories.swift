import SwiftUI
import AVFoundation

/// Everyone in the room as a row of faces, for the day the strip picked.
/// A ring means they filmed that day; tap a ringed face to watch.
struct RoomStoriesRow: View {
    let columns: [RoomFeed.Column]
    let onOpen: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(columns) { column in
                    let filmed = !column.clips.isEmpty
                    Button { onOpen(column.id) } label: {
                        VStack(spacing: 5) {
                            MemberFace(id: column.id, name: column.isMine ? nil : column.name,
                                       size: 54, isYou: column.isMine, showsMood: false)
                                .padding(3)
                                .overlay {
                                    Circle().strokeBorder(
                                        filmed ? Color.oneDayBrand : OneDay.hairline,
                                        lineWidth: filmed ? 2.5 : 1)
                                }
                            Text(column.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(filmed ? OneDay.ink : OneDay.inkFaint)
                                .lineLimit(1)
                                .frame(maxWidth: 64)
                        }
                        .opacity(filmed ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .disabled(!filmed)
                    .accessibilityIdentifier("room-story-face")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// Which person's clips the stories player opens on.
struct RoomStoriesStart: Identifiable {
    let id: String
}

/// Full screen, one person's clips of the day in the order filmed, then the
/// next person's. Each clip plays through once and moves on; tap the right
/// side to skip ahead, the left to go back.
struct RoomStoriesPlayer: View {
    /// Only people with clips, in room order.
    let columns: [RoomFeed.Column]
    let startID: String

    @Environment(\.dismiss) private var dismiss
    @State private var person = 0
    @State private var index = 0

    private var clips: [DayClip] {
        columns.indices.contains(person)
            ? columns[person].clips.sorted { ($0.recordedAt ?? .distantPast) < ($1.recordedAt ?? .distantPast) }
            : []
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if clips.indices.contains(index) {
                let clip = clips[index]
                LoopingClipPlayer(url: clip.url, refreshToken: clip.recordedAt)
                    .id(clip.id)
                    .ignoresSafeArea()
                    .task(id: clip.id) {
                        let seconds = (try? await AVURLAsset(url: clip.url).load(.duration).seconds) ?? 3
                        try? await Task.sleep(for: .seconds(max(seconds, 1)))
                        if !Task.isCancelled { step(1) }
                    }
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { step(-1) }
                    Color.clear.contentShape(Rectangle()).onTapGesture { step(1) }
                }
                .accessibilityHidden(true)
                VStack(spacing: 10) {
                    bars
                    header(clip)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
        }
        .gesture(DragGesture(minimumDistance: 40).onEnded { if $0.translation.height > 80 { dismiss() } })
        .onAppear { person = columns.firstIndex { $0.id == startID } ?? 0 }
        .statusBarHidden()
        .accessibilityIdentifier("room-stories-player")
    }

    private var bars: some View {
        HStack(spacing: 4) {
            ForEach(clips.indices, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i <= index ? 0.95 : 0.35))
                    .frame(height: 3)
            }
        }
    }

    private func header(_ clip: DayClip) -> some View {
        let column = columns[person]
        return HStack(spacing: 8) {
            MemberFace(id: column.id, name: column.isMine ? nil : column.name,
                       size: 32, isYou: column.isMine, showsMood: false)
            Text(column.name)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
            if let at = clip.recordedAt {
                Text(at.formatted(.roomClock))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.75)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Strings.close)
            .accessibilityIdentifier("room-stories-close")
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }

    /// Next or previous clip, crossing into the next or previous person;
    /// past the last clip of the last person, close.
    private func step(_ by: Int) {
        let next = index + by
        if clips.indices.contains(next) { index = next; return }
        if by > 0 {
            if person + 1 < columns.count { person += 1; index = 0 } else { dismiss() }
        } else if person > 0 {
            person -= 1
            index = max(clips.count - 1, 0)
        }
    }
}
