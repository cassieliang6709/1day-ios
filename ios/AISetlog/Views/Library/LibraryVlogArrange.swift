import SwiftUI

struct LibraryVlogArrange: View {
    @Binding var order: [LibraryClip]
    let aspectRatio: CGFloat
    let onDone: () -> Void

    @State private var previewingID: String?
    @State private var draggingID: String?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var previewing: LibraryClip? {
        order.first { $0.id == previewingID } ?? order.first
    }

    var body: some View {
        VStack(spacing: OneDay.Space.l) {
            header
            preview
            strip
            Button(Strings.libraryMakeVlogCTA, action: onDone)
                .buttonStyle(.primaryAction)
                .padding(.horizontal, OneDay.Space.xl)
                .accessibilityIdentifier("vlog-arrange-make")
        }
        .padding(.top, OneDay.Space.xl)
        .padding(.bottom, OneDay.Space.m)
    }

    private var header: some View {
        HStack {
            IconBubble(systemName: "chevron.left", action: onDone)
            Spacer()
            Text(Strings.vlogArrangeTitle)
                .font(OneDay.Font.headline)
                .foregroundStyle(OneDay.ink)
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, OneDay.Space.xl)
    }

    @ViewBuilder
    private var preview: some View {
        if let clip = previewing {
            LoopingClipPlayer(url: clip.url, refreshToken: clip.recordedAt)
                .id(clip.id)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    ClipTileLabel(text: LibrarySection.clockTime(clip.recordedAt))
                        .padding(OneDay.Space.m)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, OneDay.Space.xl)
        }
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: OneDay.Space.s) {
                    ForEach(order) { clip in
                        tile(clip)
                            .id(clip.id)
                    }
                }
                .padding(.horizontal, OneDay.Space.xl)
                .padding(.vertical, OneDay.Space.xs)
            }
            .scrollIndicators(.hidden)
            .onChange(of: previewingID) { _, id in
                guard let id else { return }
                withAnimation(OneDay.Motion.soft) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(height: 112)
    }

    private func tile(_ clip: LibraryClip) -> some View {
        let isShown = previewing?.id == clip.id
        return ClipTile(url: clip.url, refreshToken: clip.recordedAt, isSelected: isShown)
            .frame(width: 66, height: 104)
            .overlay(alignment: .bottomTrailing) {
                ClipTileLabel(text: LibrarySection.clockTime(clip.recordedAt))
                    .padding(OneDay.Space.xs)
            }
            .opacity(draggingID == clip.id ? 0.4 : 1)
            .onTapGesture { previewingID = clip.id }
            .draggable(clip.id) {
                ClipTile(url: clip.url, refreshToken: clip.recordedAt, isSelected: true)
                    .frame(width: 66, height: 104)
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
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(LibrarySection.clockTime(clip.recordedAt))
            .accessibilityIdentifier("vlog-arrange-tile-\(clip.id)")
    }

    private func move(_ id: String, to targetID: String) {
        guard id != targetID,
              let from = order.firstIndex(where: { $0.id == id }),
              let to = order.firstIndex(where: { $0.id == targetID })
        else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }
}
