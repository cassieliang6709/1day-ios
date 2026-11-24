import SwiftUI

struct LibrarySelectionCard: View {
    @Binding var picked: [LibraryClip]
    let onMake: () -> Void

    @State private var seconds: Int?
    @State private var draggingID: String?

    var body: some View {
        VStack(spacing: OneDay.Space.m) {
            if picked.isEmpty {
                Text(Strings.pickClipsHint)
                    .font(OneDay.Font.subhead)
                    .foregroundStyle(OneDay.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
            } else {
                strip
            }
            Button(Strings.libraryMakeVlog(seconds: picked.isEmpty ? nil : seconds), action: onMake)
                .buttonStyle(.primaryAction)
                .disabled(picked.isEmpty)
                .accessibilityIdentifier("library-make-vlog")
        }
        .padding(OneDay.Space.m)
        .glassSurface(radius: OneDay.Radius.card)
        .padding(.horizontal, OneDay.Space.xl)
        .task(id: picked.map(\.id)) {
            seconds = nil
            seconds = await ClipDurations.totalSeconds(of: picked.map(\.url))
        }
    }

    private static let tileWidth: CGFloat = 56
    private static let tileHeight: CGFloat = 88

    private var strip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: OneDay.Space.s) {
                ForEach(Array(picked.enumerated()), id: \.element.id) { index, clip in
                    tile(clip, number: index + 1)
                }
            }
            .padding(.vertical, OneDay.Space.xs)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("library-selected-strip")
    }

    private func tile(_ clip: LibraryClip, number: Int) -> some View {
        ClipTile(url: clip.url, refreshToken: clip.recordedAt, bedsInsteadOfCrops: true)
            .frame(width: Self.tileWidth, height: Self.tileHeight)
            .overlay(alignment: .bottomLeading) {
                Text("\(number)")
                    .font(OneDay.Font.micro)
                    .foregroundStyle(OneDay.onBrand)
                    .frame(width: 20, height: 20)
                    .background(Color.oneDayBrand, in: Circle())
                    .padding(OneDay.Space.xs)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(OneDay.Motion.snap) { picked.removeAll { $0.id == clip.id } }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(OneDay.Font.headline)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.libraryRemovePicked)
            }
            .opacity(draggingID == clip.id ? 0.4 : 1)
            .draggable(clip.id) {
                ClipTile(url: clip.url, refreshToken: clip.recordedAt, isSelected: true)
                    .frame(width: Self.tileWidth, height: Self.tileHeight)
                    .onAppear { draggingID = clip.id }
            }
            .dropDestination(for: String.self) { ids, _ in
                draggingID = nil
                guard let id = ids.first else { return false }
                move(id, to: clip.id)
                return true
            } isTargeted: { targeted in
                guard targeted, let dragging = draggingID else { return }
                withAnimation(OneDay.Motion.soft) { move(dragging, to: clip.id) }
            }
    }

    private func move(_ id: String, to targetID: String) {
        guard id != targetID,
              let from = picked.firstIndex(where: { $0.id == id }),
              let to = picked.firstIndex(where: { $0.id == targetID })
        else { return }
        picked.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }
}

struct VlogRequest: Identifiable {
    let clips: [LibraryClip]
    var id: String { clips.map(\.id).joined(separator: "|") }
}
