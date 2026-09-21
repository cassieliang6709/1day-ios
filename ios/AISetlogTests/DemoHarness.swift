import Foundation

/// What the shared-room tests ask the stand-in clip generator for.
///
/// These suites drive the real `ChallengeStore`, `RoomSyncService` and
/// `VideoStitcher` through the local-room harness. What they are checking is
/// wiring — who owns which clip, what the canvas comes out as, what gets
/// cleaned up — and none of it needs three seconds of footage.
///
/// It needs *some* footage. Half a second at 30fps is fifteen frames: enough
/// for a crossfade to have somewhere to happen, for the look pass to run more
/// than once, and for two sampled frames to differ. Below that the tests stop
/// exercising the thing they are named after.
///
/// Why it is worth a constant: the stitch costs per output frame, the CI
/// runner has no GPU, and these suites were 39 of the job's 65 minutes. Six
/// times shorter is most of that back.
enum DemoHarness {
    static let clipSeconds: Double = 0.5
}
