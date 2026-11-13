import Foundation

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
