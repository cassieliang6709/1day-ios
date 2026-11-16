import AppIntents
import Foundation

@available(iOS 18.0, *)
struct OneDayCaptureIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "1Day"

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "capture.launchRequested")
        NotificationCenter.default.post(name: .oneDayCaptureRequested, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let oneDayCaptureRequested = Notification.Name("oneDayCaptureRequested")
    static let oneDayCapturedDraftsRequested = Notification.Name("oneDayCapturedDraftsRequested")
}

struct LockedCaptureManifest: Codable {
    let id: UUID
    let recordedAt: Date
    let landscape: Bool

    var movieName: String { "\(id.uuidString).mov" }
    var manifestName: String { "\(id.uuidString).json" }
}

enum CaptureText {
    static func localized(_ english: String, _ chinese: String) -> String {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
    }
}
