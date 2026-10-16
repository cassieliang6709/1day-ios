import AVFoundation
import AVKit
import SwiftUI

/// Under a finished film: 原声 / 音乐 / 混合, 换一首, and 加旁白. Each change
/// remixes `baseURL` into a new file and hands it back through `mixedURL`;
/// the film's player, save and share use that file once it lands.
///
/// Starts on 混合 with a track picked for the day's mood, so a film has music
/// without anyone asking for it.
struct FilmSoundtrackPanel: View {
    let baseURL: URL
    let mood: Mood?
    @Binding var mixedURL: URL?

    @State private var mode: FilmSoundtrack.Mode = .mix
    @State private var track: FilmSoundtrack.Track?
    @State private var voiceover: URL?
    @State private var working = false
    @State private var failed = false
    @State private var recording = false

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private struct Request: Equatable {
        let base: URL
        let mode: FilmSoundtrack.Mode
        let track: String?
        let voiceover: URL?
    }

    private var request: Request {
        Request(base: baseURL, mode: mode, track: track?.id, voiceover: voiceover)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Strings.soundTitle)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Spacer()
                if working {
                    ProgressView().controlSize(.small)
                    Text(Strings.soundWorking)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                }
            }

            Picker(Strings.soundTitle, selection: $mode) {
                Text(Strings.soundOriginal).tag(FilmSoundtrack.Mode.original)
                Text(Strings.soundMusic).tag(FilmSoundtrack.Mode.music)
                Text(Strings.soundMix).tag(FilmSoundtrack.Mode.mix)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("film-sound-mode")

            HStack(spacing: 10) {
                if mode != .original, let track {
                    Button {
                        self.track = FilmSoundtrack.pick(for: mood, excluding: track)
                    } label: {
                        Label("\(Strings.soundTrackName(track.id)) · \(Strings.soundNextTrack)",
                              systemImage: "shuffle")
                    }
                    .accessibilityIdentifier("film-sound-next")
                }
                Spacer(minLength: 0)
                Menu {
                    Button(voiceover == nil ? Strings.voiceoverAdd : Strings.voiceoverRedo) { recording = true }
                    if voiceover != nil {
                        Button(Strings.voiceoverRemove, role: .destructive) { voiceover = nil }
                    }
                } label: {
                    Label(voiceover == nil ? Strings.voiceoverAdd : Strings.voiceoverRedo,
                          systemImage: voiceover == nil ? "mic" : "mic.fill")
                } primaryAction: {
                    recording = true
                }
                .accessibilityIdentifier("film-voiceover")
            }
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            .foregroundStyle(OneDay.brandText)

            if failed {
                Text(Strings.soundFailed)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
            }
        }
        .padding(14)
        .glassSurface(radius: OneDay.Radius.card)
        .onAppear { if track == nil { track = FilmSoundtrack.pick(for: mood) } }
        .task(id: request) { await remix() }
        .sheet(isPresented: $recording) {
            VoiceoverRecorder(film: baseURL) { voiceover = $0 }
        }
    }

    private func remix() async {
        guard track != nil || mode == .original else { return }
        working = true
        failed = false
        defer { working = false }
        do {
            let url = try await FilmSoundtrack.render(
                film: baseURL, mode: mode, track: track, voiceover: voiceover)
            guard !Task.isCancelled else { return }
            let old = mixedURL
            mixedURL = url == baseURL ? nil : url
            if let old, old != url { try? FileManager.default.removeItem(at: old) }
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            mixedURL = nil
        }
    }
}

/// Plays the film from the top while recording the microphone, and stops
/// when the film ends. The take is handed back only on 用这段.
private struct VoiceoverRecorder: View {
    let film: URL
    let onUse: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var recorder: AVAudioRecorder?
    @State private var take: URL?
    @State private var isRecording = false
    @State private var denied = false
    @State private var endObserver: NSObjectProtocol?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    init(film: URL, onUse: @escaping (URL) -> Void) {
        self.film = film
        self.onUse = onUse
        _player = State(initialValue: AVPlayer(url: film))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(Strings.voiceoverTitle)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Spacer()
                IconBubble(systemName: "xmark") { close() }
            }
            Text(denied ? Strings.voiceoverDenied : Strings.voiceoverHint)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)

            VideoPlayer(player: player)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if isRecording {
                        Label(Strings.voiceoverRecording, systemImage: "record.circle")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.red, in: Capsule())
                            .padding(10)
                    }
                }

            if isRecording {
                Button(Strings.voiceoverStop) { stop() }
                    .buttonStyle(.primaryAction)
            } else if let take {
                HStack(spacing: 10) {
                    Button(Strings.voiceoverRetake) { Task { await start() } }
                        .buttonStyle(.softAction)
                    Button(Strings.voiceoverUse) {
                        onUse(take)
                        close()
                    }
                    .buttonStyle(.primaryAction)
                }
            } else {
                Button(Strings.voiceoverStart) { Task { await start() } }
                    .buttonStyle(.primaryAction)
                    .disabled(denied)
                    .accessibilityIdentifier("voiceover-start")
            }
        }
        .padding(20)
        .background(OneDay.canvas)
        .onDisappear { teardown() }
    }

    private func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            denied = true
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            // Speaker, not the earpiece, so the film is heard while talking.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voiceover_\(UUID().uuidString).m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
            ])
            take = nil
            self.recorder = recorder
            await player.seek(to: .zero)
            player.volume = 0.6
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: player.currentItem, queue: .main
            ) { _ in Task { @MainActor in stop() } }
            recorder.record()
            player.play()
            isRecording = true
        } catch {
            print("[voiceover] start failed: \(error)")
            teardown()
        }
    }

    private func stop() {
        guard isRecording else { return }
        player.pause()
        recorder?.stop()
        take = recorder?.url
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func teardown() {
        if isRecording { stop() }
        player.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func close() {
        teardown()
        dismiss()
    }
}
