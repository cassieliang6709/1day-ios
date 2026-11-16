import Foundation

enum DemoEntries {
    static let launchArgument = "-demoEntries"

    static var areEnabled: Bool {
        UserDefaults.standard.bool(forKey: "demoEntries")
    }
}
