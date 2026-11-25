import SwiftUI

struct RoomPersonPage: View {
    let column: RoomFeed.Column
    var slotTitle: (Int) -> String? = { _ in nil }
    let onPlay: (DayClip) -> Void
    var canPoke = false
    var hasPoked = false
    var onPoke: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var pokedNow = false

    private static let tileAspect: CGFloat = 3 / 4

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        MemberFace(id: column.id, name: column.isMine ? nil : column.name, size: 44,
                                   isYou: column.isMine)
                        Text(column.name)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(OneDay.ink)
                            .lineLimit(1)
                        Spacer(minLength: OneDay.Space.s)
                        if canPoke { pokeButton }
                    }

                    if !column.clips.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10),
                                      GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(column.clips) { clip in tile(clip) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    IconBubble(systemName: "chevron.left", label: Strings.back) { dismiss() }
                        .accessibilityIdentifier("room-person-back")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: OneDay.tabBarClearance)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var pokeButton: some View {
        let sent = pokedNow || hasPoked
        return Button {
            onPoke()
            pokedNow = true
        } label: {
            Label(sent ? Strings.roomTilePoked : Strings.roomTilePoke,
                  systemImage: sent ? "checkmark" : "hand.tap.fill")
                .font(OneDay.Font.callout)
                .foregroundStyle(sent ? OneDay.inkFaint : OneDay.brandText)
                .padding(.horizontal, OneDay.Space.m)
                .frame(minHeight: 40)
                .background(OneDay.surfaceSoft, in: Capsule())
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(sent)
        .accessibilityIdentifier("room-person-poke")
    }

    private func tile(_ clip: DayClip) -> some View {
        let title = slotTitle(clip.day)
        return Button { onPlay(clip) } label: {
            Color.clear
                .aspectRatio(Self.tileAspect, contentMode: .fit)
                .overlay { ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt) }
                .overlay {
                    LinearGradient(
                        colors: [.clear, .clear, .black.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let at = clip.recordedAt, !Calendar.current.isDateInToday(at) {
                            Text(at.formatted(.dateTime.month().day()
                                .locale(AppLanguage.effective.locale)))
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .opacity(0.85)
                        }
                        if let at = clip.recordedAt {
                            Text(at.formatted(.roomClock))
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                        }
                        if let title {
                            Text(title)
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("room-person-clip")
    }
}
