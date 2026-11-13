import Foundation
import UIKit
#if DEBUG
import UIKit.UIGestureRecognizerSubclass
#endif

/// Debug-only trace of the avatar flow, for the UI test.
///
/// Only writes when `-debugAvatarSample` is set (the UI test, or someone
/// feeding a sample by hand). Each line is a wall-clock timestamp and an
/// event, appended to a file the test process on the same Mac can read and
/// print when the flow doesn't close. A main-thread watchdog notes stalls.
enum AvatarFlowTrace {
    static let path = "/tmp/1day-uitest-avatar-trace.log"

    static func log(_ event: @autoclosure () -> String) {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "debugAvatarSample") != nil else { return }
        let line = String(format: "%.3f ", Date().timeIntervalSince1970)
            + event() + (Thread.isMainThread ? "" : " [bg]") + "\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
        startWatchdogOnce()
        #endif
    }

    #if DEBUG
    private static let queue = DispatchQueue(label: "avatar-trace")
    private static var watchdogStarted = false
    private static var lastTick = Date()

    private static func startWatchdogOnce() {
        guard Thread.isMainThread, !watchdogStarted else { return }
        watchdogStarted = true
        lastTick = Date()
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            let gap = Date().timeIntervalSince(lastTick)
            lastTick = Date()
            if gap > 1 { log(String(format: "main stalled %.2fs", gap)) }
        }
    }
    #endif
}

#if DEBUG
/// Logs every touch the window gets while the trace is on, with what UIKit
/// hit-tested, so a lost tap can be told apart from a tap the button ignored.
/// It never recognises, so it doesn't take touches from anything.
final class AvatarTouchTraceRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private static var installed = false

    static func installIfTracing() {
        guard UserDefaults.standard.string(forKey: "debugAvatarSample") != nil, !installed else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)
        else {
            AvatarFlowTrace.log("touch trace: no key window yet")
            return
        }
        installed = true
        let recognizer = AvatarTouchTraceRecognizer(target: nil, action: nil)
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = recognizer
        window.addGestureRecognizer(recognizer)
        AvatarFlowTrace.log("touch trace installed windows=\(window.windowScene?.windows.count ?? 0)")
    }

    private func note(_ phase: String, _ touches: Set<UITouch>, _ event: UIEvent) {
        for touch in touches {
            let point = touch.location(in: view)
            let hit = view?.hitTest(point, with: event)
            AvatarFlowTrace.log(String(format: "touch %@ at (%.0f,%.0f) hit=%@ touchView=%@",
                                       phase, point.x, point.y,
                                       hit.map { String(describing: type(of: $0)) } ?? "nil",
                                       touch.view.map { String(describing: type(of: $0)) } ?? "nil"))
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event); note("began", touches, event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event); note("ended", touches, event); state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event); note("cancelled", touches, event); state = .failed
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif
