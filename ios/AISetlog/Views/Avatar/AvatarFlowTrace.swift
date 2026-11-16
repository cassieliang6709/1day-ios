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
/// print when the flow doesn't close.
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
        #endif
    }

    #if DEBUG
    private static let queue = DispatchQueue(label: "avatar-trace")
    #endif
}

#if DEBUG
/// Logs every touch the window gets while the trace is on, with what UIKit
/// hit-tested and which recognisers held it. It never recognises, and it
/// recognises alongside everything else, so it takes no touch from anyone; it
/// gets `touchesCancelled` when the touch itself is cancelled under the app,
/// which is what the UI test looks for.
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
            let recognizers = (touch.gestureRecognizers ?? []).filter { $0 !== self }.map {
                "\(type(of: $0))[\($0.state.rawValue)]@\($0.view.map { String(describing: type(of: $0)) } ?? "nil")"
            }
            AvatarFlowTrace.log("  app=\(UIApplication.shared.applicationState.rawValue) "
                + "scene=\(view?.window?.windowScene?.activationState.rawValue ?? -9) "
                + "key=\(view?.window?.isKeyWindow ?? false) recognizers=\(recognizers)")
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
