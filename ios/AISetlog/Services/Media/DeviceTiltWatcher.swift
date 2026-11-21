import CoreMotion
import Foundation
import Observation

@MainActor
@Observable
final class DeviceTiltWatcher {
    private(set) var isHeldSideways = false

    private let motion = CMMotionManager()
    private var sidewaysSince: Date?
    private let holdSeconds: TimeInterval

    init(holdSeconds: TimeInterval = 0.5) {
        self.holdSeconds = holdSeconds
    }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gravity = data?.gravity else { return }
            MainActor.assumeIsolated { self.update(x: gravity.x, y: gravity.y, z: gravity.z) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        sidewaysSince = nil
        isHeldSideways = false
    }

    private func update(x: Double, y: Double, z: Double) {
        let sideways = abs(x) > 0.45 && abs(x) > 2 * abs(y) && abs(z) < 0.9
        guard sideways else {
            sidewaysSince = nil
            isHeldSideways = false
            return
        }
        let since = sidewaysSince ?? .now
        sidewaysSince = since
        if Date.now.timeIntervalSince(since) >= holdSeconds { isHeldSideways = true }
    }
}
