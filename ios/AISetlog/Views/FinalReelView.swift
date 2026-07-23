import SwiftUI
import AVKit
import Photos

struct FinalReelView: View {
    let challenge: Challenge
    let clips: [DayClip]

    @State private var layout: VideoStitcher.Layout
    @State private var exportURLs: [VideoStitcher.Layout: URL] = [:]
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var isSavingVideo = false
    @State private var saveMessage: String?

    // Simple edit controls (Adjust sheet)
    @State private var showAdjust = false
    @State private var includeTitleCard = true
    @State private var includeCaptions = true
    @State private var fadeSeconds = 0.35
    @State private var gridSeconds = 6.0

    init(challenge: Challenge, clips: [DayClip]) {
        self.challenge = challenge
        self.clips = clips
        var initial = VideoStitcher.Layout.sequential
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoGrid") { initial = .grid }
        #endif
        _layout = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Layout", selection: $layout) {
                Text("Sequence").tag(VideoStitcher.Layout.sequential)
                Text("Grid").tag(VideoStitcher.Layout.grid)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                if let player, exportURLs[layout] != nil {
                    VStack(spacing: 16) {
                        VideoPlayer(player: player)
                            .aspectRatio(9 / 16, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 20))

                        Text(footerText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let url = exportURLs[layout] {
                            VStack(spacing: 10) {
                                ShareLink(item: url) {
                                    Label(shareButtonTitle, systemImage: "square.and.arrow.up")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)

                                Button {
                                    Task { await saveVideo(url) }
                                } label: {
                                    Label(isSavingVideo ? "Saving…" : "Save video", systemImage: "square.and.arrow.down")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .disabled(isSavingVideo)

                                if let saveMessage {
                                    Text(saveMessage)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Stitching failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text(layout == .grid
                            ? "Building the grid…"
                            : "Stitching your week together…")
                            .font(.headline)
                        Text("Rendered on-device with AVFoundation")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(challenge.isOneDay ? "1-Day Film" : "Weekly Film")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdjust = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showAdjust) {
            AdjustSheet(
                includeTitleCard: $includeTitleCard,
                includeCaptions: $includeCaptions,
                fadeSeconds: $fadeSeconds,
                gridSeconds: $gridSeconds
            ) {
                exportURLs.removeAll()
                Task { await render() }
            }
            .presentationDetents([.medium])
        }
        .task(id: layout) { await render() }
        .onDisappear { player?.pause() }
    }

    private var footerText: String {
        switch layout {
        case .sequential:
            return "\(clips.count) \(challenge.unitName)\(clips.count == 1 ? "" : "s") · crossfades"
        case .grid:
            return "\(clips.count) clip\(clips.count == 1 ? "" : "s") looping side by side"
        }
    }

    private var shareButtonTitle: String {
        challenge.isOneDay ? "Share 1-day film" : "Share weekly film"
    }

    private func render() async {
        errorMessage = nil
        if let cached = exportURLs[layout] {
            play(cached)
            return
        }
        player?.pause()
        player = nil
        do {
            var options = VideoStitcher.Options()
            options.layout = layout
            options.crossfadeSeconds = fadeSeconds
            options.gridSeconds = gridSeconds
            options.showDayCaptions = includeCaptions
            options.titleCard = includeTitleCard ? titleCard : nil
            let url = try await VideoStitcher.stitch(clips: clips, options: options)
            exportURLs[layout] = url
            play(url)
        } catch {
            print("[stitch] failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func play(_ url: URL) {
        let player = AVPlayer(url: url)
        self.player = player
        player.play()
    }

    private func saveVideo(_ url: URL) async {
        isSavingVideo = true
        saveMessage = nil
        defer { isSavingVideo = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveMessage = "Photos access is needed to save the video."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            saveMessage = "Saved to Photos."
        } catch {
            saveMessage = "Couldn't save video: \(error.localizedDescription)"
        }
    }

    private var titleCard: VideoStitcher.TitleCard {
        let start = challenge.startDate
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        if challenge.isOneDay {
            return VideoStitcher.TitleCard(
                title: challenge.title,
                subtitle: "1-day film · \(clips.count)/\(challenge.cards.count) \(challenge.resolvedClipLength.secondsLabel) moments")
        }
        return VideoStitcher.TitleCard(
            title: challenge.title,
            subtitle: "\(start.formatted(fmt)) – \(end.formatted(fmt))")
    }
}

/// Lightweight editing controls: what goes into the render.
private struct AdjustSheet: View {
    @Binding var includeTitleCard: Bool
    @Binding var includeCaptions: Bool
    @Binding var fadeSeconds: Double
    @Binding var gridSeconds: Double
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Overlays") {
                    Toggle("Opening title card", isOn: $includeTitleCard)
                    Toggle("Day captions", isOn: $includeCaptions)
                }
                Section {
                    HStack {
                        Text("Transition")
                        Slider(value: $fadeSeconds, in: 0...0.6, step: 0.05)
                        Text(fadeSeconds == 0 ? "Cut" : String(format: "%.2fs", fadeSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                } header: {
                    Text("Sequence")
                } footer: {
                    Text("0 = hard cuts for a snappier diary film.")
                }
                Section("Grid") {
                    HStack {
                        Text("Length")
                        Slider(value: $gridSeconds, in: 4...12, step: 1)
                        Text("\(Int(gridSeconds))s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .navigationTitle("Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        dismiss()
                        onApply()
                    }
                    .bold()
                }
            }
        }
    }
}
