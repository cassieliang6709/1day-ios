import SwiftUI
import AVFoundation

/// Looping playback of a single day's clip, with emoji reactions, a comment
/// thread, and the option to re-record.
struct ClipPreviewView: View {
    let day: Int
    var slotTitle: String?
    var authorName: String?
    var overlayText: String?
    var clipLength: Challenge.ClipLength = .tiny
    let url: URL
    let recordedAt: Date?
    var challengeID: UUID?
    let onReRecord: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var draftComment = ""
    @FocusState private var commentFocused: Bool

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var myID: String { account.account?.id ?? "local" }

    private var card: DayCard? {
        guard let challengeID else { return nil }
        return store.challenge(challengeID)?.cards.first { $0.day == day }
    }
    private var reactions: [ClipReaction] { card?.reactions ?? [] }
    private var comments: [ClipComment] {
        (card?.comments ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    clip
                        .frame(maxWidth: 340)
                        .frame(maxWidth: .infinity)

                    if challengeID != nil {
                        reactionBar
                    }

                    if let recordedAt {
                        Text(Strings.capturedAt(recordedAt.formatted(date: .abbreviated, time: .shortened)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if challengeID != nil {
                        commentsSection
                    }

                    Button {
                        onReRecord()
                    } label: {
                        Label(Strings.rerecord, systemImage: "arrow.counterclockwise.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(slotTitle ?? Strings.dayN(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if challengeID != nil { commentInput }
            }
        }
    }

    private var clip: some View {
        ZStack {
            LoopingClipPlayer(url: url)
            MomentStampOverlay(
                name: authorName,
                momentTitle: slotTitle ?? Strings.dayN(day),
                day: day,
                mode: .review,
                timestamp: recordedAt,
                overlayText: overlayText,
                clipSeconds: clipLength.seconds
            )
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Identity.tint(for: authorName), lineWidth: 3)
        }
    }

    // MARK: - Reactions

    private var reactionBar: some View {
        HStack(spacing: 8) {
            ForEach(ClipReaction.palette, id: \.self) { emoji in
                let count = reactions.filter { $0.emoji == emoji }.count
                let mine = reactions.contains { $0.emoji == emoji && $0.authorID == myID }
                Button {
                    if let challengeID {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.toggleReaction(emoji, day: day, challengeID: challengeID)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(emoji).font(.system(size: 18))
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption.bold())
                                .foregroundStyle(mine ? Color.oneDayBlue : .secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(mine ? Color.oneDaySky.opacity(0.5) : Color.gray.opacity(0.12)))
                    .overlay(
                        Capsule().strokeBorder(
                            mine ? Color.oneDayBlue.opacity(0.6) : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: mine)
            }
        }
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(comments.isEmpty ? Strings.comments : Strings.commentsCount(comments.count))
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if comments.isEmpty {
                Text(Strings.firstComment)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(comments) { comment in
                    CommentRow(comment: comment, isMine: comment.authorID == myID) {
                        if let challengeID {
                            store.deleteComment(comment.id, day: day, challengeID: challengeID)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commentInput: some View {
        HStack(spacing: 10) {
            TextField(Strings.addComment, text: $draftComment, axis: .vertical)
                .lineLimit(1...4)
                .focused($commentFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.gray.opacity(0.14)))
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.oneDayBlue : Color.gray.opacity(0.4))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend, let challengeID else { return }
        store.addComment(draftComment, day: day, challengeID: challengeID)
        draftComment = ""
        commentFocused = false
    }
}

private struct CommentRow: View {
    let comment: ClipComment
    let isMine: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Identity.initial(for: comment.authorName))
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Identity.tint(for: comment.authorName).gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.footnote.bold())
                    Text(comment.createdAt, format: .relative(presentation: .numeric))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(comment.text)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if isMine {
                Button(Strings.delete, systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }
}

/// Endlessly looping muted-free playback of one clip. Fills its frame like
/// the live camera preview does (`.resizeAspectFill`) — SwiftUI's `VideoPlayer`
/// aspect-*fits* by default, which is what was letterboxing recorded clips
/// with black bars whenever the footage didn't exactly match the frame.
struct LoopingClipPlayer: View {
    let url: URL

    var body: some View {
        LoopingPlayerLayerView(url: url)
    }
}

private struct LoopingPlayerLayerView: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        let queuePlayer = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = queuePlayer
        queuePlayer.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
    }
}

/// First-frame thumbnail of a clip, loaded off the main thread.
struct ClipThumbnail: View {
    let url: URL
    /// Changing this value (e.g. recordedAt) forces a reload after re-recording.
    var refreshToken: Date?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray5)
            }
        }
        .task(id: refreshToken) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                image = UIImage(cgImage: cgImage)
            }
        }
    }
}
