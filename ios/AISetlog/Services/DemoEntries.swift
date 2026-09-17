import Foundation

/// Whether the app shows its demo affordances: 「房间演示」 on the home screen
/// and 「使用示例片段」 in the camera.
///
/// Both were `#if DEBUG`, so they never shipped — but "never shipped" and "not
/// in the way" are different things. They were in the way of the person who
/// looks at a Debug build every day, which is the whole of 1.3's 冗余内容清理.
///
/// Deleting them outright was the instruction, and it would have cost two
/// things worth more than the clutter: the ability to demo the app without
/// three people and a camera, and `LocalFormalRoomUITests`,
/// `LocalFormalMomentUITests` and `LocalRoomImportUITests`, whose only way in
/// is that home-screen button. The Simulator has no camera at all, so on a
/// Mac these entries are the only way to get footage into a story.
///
/// So they are off by default and opt-in by launch argument instead. Nothing
/// sees them unless it asks:
///
/// ```
/// app.launchArguments = ["-demoEntries", "YES"]
/// ```
///
/// Still inside `#if DEBUG` at the call sites: this decides whether a Debug
/// build draws them, not whether a Release build could.
enum DemoEntries {
    static let launchArgument = "-demoEntries"

    /// Read fresh rather than cached in a `let`. A cached value is read once at
    /// class-load time, which on the UI-test path is before the arguments this
    /// looks at have been applied.
    static var areEnabled: Bool {
        UserDefaults.standard.bool(forKey: "demoEntries")
    }
}
