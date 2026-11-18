import AVFoundation
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class SpeechDictation {
    enum Status: Equatable {
        case idle
        case listening
        case denied
        case unavailable
    }

    private(set) var status: Status = .idle
    private(set) var transcript = ""

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var generation = 0

    var isListening: Bool { status == .listening }

    static func locale(for language: AppLanguage) -> Locale {
        Locale(identifier: language.resolved == .chinese ? "zh-CN" : "en-US")
    }

    func toggle(language: AppLanguage) async {
        if isListening { stop() } else { await start(language: language) }
    }

    func start(language: AppLanguage) async {
        guard !isListening else { return }
        transcript = ""
        guard await Self.requestPermissions() else { status = .denied; return }
        guard let recognizer = SFSpeechRecognizer(locale: Self.locale(for: language)),
              recognizer.isAvailable else { status = .unavailable; return }
        do {
            try begin(with: recognizer)
            status = .listening
        } catch {
            print("[dictation] start failed: \(error)")
            stop()
            status = .unavailable
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if status == .listening { status = .idle }
    }

    private func begin(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()

        generation += 1
        let current = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                if let text { self.transcript = text }
                if done { self.stop() }
            }
        }
    }

    private static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
