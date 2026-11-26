import SwiftUI

struct RoomLockedFace: View {
    let clip: DayClip
    let meta: String
    let onUnlock: () -> Void

    var body: some View {
        Button(action: onUnlock) {
            Color.clear
                .overlay {
                    ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt, bedsInsteadOfCrops: true)
                        .blur(radius: 28, opaque: true)
                }
                .overlay { Color.black.opacity(0.18) }
                .clipped()
                .overlay {
                    VStack(spacing: OneDay.Space.s) {
                        Image(systemName: "lock.fill")
                            .font(OneDay.Font.title)
                        Label(Strings.roomPeekLocked, systemImage: "camera.fill")
                            .font(OneDay.Font.callout)
                            .foregroundStyle(OneDay.onBrand)
                            .padding(.horizontal, OneDay.Space.m)
                            .frame(height: 38)
                            .background(Color.oneDayBrand, in: Capsule())
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text(meta)
                        .font(OneDay.Font.caption)
                        .lineLimit(1)
                        .padding(OneDay.Space.m)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text([meta, Strings.roomPeekLocked].joined(separator: ", ")))
        .accessibilityIdentifier("room-clip-locked")
    }
}
