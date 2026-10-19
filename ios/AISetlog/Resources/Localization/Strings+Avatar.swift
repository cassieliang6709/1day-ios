import Foundation

/// Copy for the avatar flow (《DayDay 注册与 Avatar 生成 V1》) and the mood
/// face shown in rooms. Kept out of `Localization.swift` so parallel edits
/// don't collide.
extension Strings {
    private static func avatar(_ zh: String, _ en: String) -> String {
        AppLanguage.effective.resolved == .chinese ? zh : en
    }

    // Upload
    static var avatarUploadTitle: String { avatar("给我看看你", "Show me you") }
    static var avatarUploadHeadline: String { avatar("用一张照片，画一个你。", "One photo, and we'll draw you.") }
    static var avatarUploadSubtitle: String { avatar("拍一张，或从相册挑。", "Take one, or pick from your photos.") }
    static var avatarTakePhoto: String { avatar("拍一张", "Take one") }
    static var avatarPickPhoto: String { avatar("从相册挑", "Pick from Photos") }
    static var avatarFrontFacingHint: String { avatar("正面照效果最好", "A front-facing photo works best") }
    static var avatarSkip: String { avatar("先不用头像", "Not now") }
    static var avatarCameraPermission: String {
        avatar("要用相机拍一张你的照片。只用来画头像，不会上传原图。",
               "The camera takes one photo of you. It's only used to draw your avatar, and the photo is never uploaded.")
    }
    static var avatarCameraContinue: String { avatar("好", "OK") }
    static var avatarFailed: String { avatar("这张没画出来，换一张试试。", "That one didn't work. Try another photo.") }

    // Generating
    static var avatarGeneratingHeadline: String { avatar("正在画你。", "Drawing you.") }
    static var avatarGeneratingSubtitle: String { avatar("几秒钟。", "A few seconds.") }

    // Confirm
    static var avatarConfirmHeadline: String { avatar("画好了。这是你。", "Done. This is you.") }
    static var avatarConfirm: String { avatar("就是这样", "That's me") }
    static var avatarRedraw: String { avatar("重画一张", "Draw another") }
    static var avatarDone: String { avatar("好了，去记今天。", "All set. Go film today.") }
    static var avatarAccessibility: String { avatar("你的头像", "Your avatar") }

    // Settings
    static var avatarRedoHint: String { avatar("点一下重画头像", "Tap to redraw your avatar") }

    // Rooms
    static func memberMoodAccessibility(name: String, mood: String) -> String {
        avatar("\(name)，今天\(mood)", "\(name), feeling \(mood.lowercased()) today")
    }
}
