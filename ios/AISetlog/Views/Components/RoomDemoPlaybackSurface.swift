#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import UIKit
import AVFoundation
import CoreImage

/// Demo-only rendering of actual decoded frames, driven by AVPlayer's clock.
/// Device diagnostics showed valid decode and advancing playback but a black
/// AVPlayerLayer. This path does not use a static poster as a video substitute.
final class RoomDemoPlaybackSurface: UIView {
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let url: URL
    private let queue = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var output: AVPlayerItemVideoOutput?
    private weak var outputItem: AVPlayerItem?
    private var orientationTask: Task<Void, Never>?
    private var imageTransform = CGAffineTransform.identity
    private var orientationReady = false
    private var timeout: Timer?
    private var notifications: [NSObjectProtocol] = []
    private let status = UILabel()
    private let retry = UIButton(type: .system)
    private let picture = UIImageView()
    private(set) var renderedFrameCount = 0
    private var stopped = false
    private var chinese: Bool {
        let preference = UserDefaults.standard.string(forKey: "appLanguage")
        if preference == "chinese" { return true }
        if preference == "english" { return false }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        backgroundColor = .black
        queue.isMuted = true
        queue.allowsExternalPlayback = false
        picture.contentMode = .scaleAspectFit
        picture.isAccessibilityElement = true
        picture.accessibilityIdentifier = "room-demo-decoded-video"
        picture.accessibilityLabel = chinese ? "示例视频" : "Sample video"
        addSubview(picture)
        status.textColor = .white
        status.numberOfLines = 0
        status.textAlignment = .center
        status.font = .preferredFont(forTextStyle: .caption1)
        status.accessibilityIdentifier = "room-demo-playback-status"
        retry.setTitle(chinese ? "重试播放" : "Retry playback", for: .normal)
        retry.addTarget(self, action: #selector(restart), for: .touchUpInside)
        addSubview(status)
        addSubview(retry)
        orientationTask = Task { @MainActor [weak self, url] in
            let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video)
            let transform = try? await tracks?.first?.load(.preferredTransform)
            guard !Task.isCancelled else { return }
            self?.imageTransform = transform ?? .identity
            self?.orientationReady = true
        }
        statusObservation = queue.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.observeCurrentItem() }
        }
        timeObserver = queue.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 15), queue: .main
        ) { [weak self] time in self?.presentFrame(at: time) }
        notifications.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.queue.pause() })
        notifications.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.stopped, self.window != nil else { return }
            self.queue.play()
        })
        restart()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        picture.frame = bounds
        status.frame = CGRect(x: 12, y: max(0, bounds.midY - 48), width: max(0, bounds.width - 24), height: 64)
        retry.frame = CGRect(x: 12, y: bounds.midY + 18, width: max(0, bounds.width - 24), height: 44)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { queue.pause() } else if !stopped { queue.play() }
    }

    @objc private func restart() {
        guard !stopped else { return }
        timeout?.invalidate()
        itemObservation = nil
        detachOutput()
        looper?.disableLooping()
        queue.removeAllItems()
        renderedFrameCount = 0
        picture.image = nil
        status.isHidden = false
        status.text = chinese ? "正在加载视频…" : "Loading video…"
        retry.isHidden = true
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        observeCurrentItem()
        if window != nil { queue.play() }
        timeout = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self, self.renderedFrameCount == 0 else { return }
            self.showFailure(nil)
        }
    }

    private func detachOutput() {
        if let output, let outputItem { outputItem.remove(output) }
        output = nil
        outputItem = nil
    }

    private func observeCurrentItem() {
        guard !stopped, let item = queue.currentItem, item !== outputItem else { return }
        detachOutput()
        let next = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(next)
        output = next
        outputItem = item
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { self?.showFailure(item.error as NSError?) }
        }
    }

    private func presentFrame(at time: CMTime) {
        guard !stopped, window != nil, orientationReady, let output,
              output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: imageTransform)
        guard let cgImage = Self.imageContext.createCGImage(image, from: image.extent) else { return }
        picture.image = UIImage(cgImage: cgImage)
        renderedFrameCount += 1
        if CommandLine.arguments.contains("-roomPlaybackDiagnostics") {
            picture.accessibilityValue = "frames=\(renderedFrameCount);time=\(time.seconds)"
        }
        status.isHidden = true
        retry.isHidden = true
        timeout?.invalidate()
    }

    private func showFailure(_ error: NSError?) {
        guard !stopped else { return }
        timeout?.invalidate()
        status.isHidden = false
        status.text = chinese ? "视频未能显示，请重试。" : "Video could not be displayed. Please retry."
        if let error { status.text! += "\n\(error.domain) (\(error.code))" }
        retry.isHidden = false
    }

    func stop() {
        stopped = true
        timeout?.invalidate()
        orientationTask?.cancel()
        if let timeObserver { queue.removeTimeObserver(timeObserver) }
        timeObserver = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications = []
        statusObservation = nil
        itemObservation = nil
        queue.pause()
        detachOutput()
        looper?.disableLooping()
        looper = nil
        queue.removeAllItems()
        picture.image = nil
    }

    deinit {
        timeout?.invalidate()
        orientationTask?.cancel()
        if let timeObserver { queue.removeTimeObserver(timeObserver) }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
#endif
