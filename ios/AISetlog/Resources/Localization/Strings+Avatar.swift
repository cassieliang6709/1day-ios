import Foundation

extension Strings {
    private static func avatar(_ zh: String, _ en: String) -> String {
        AppLanguage.effective.resolved == .chinese ? zh : en
    }

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
    static var avatarFailed: String { avatar("没画出来，换一张", "That one didn't work. Try another photo.") }

    static var avatarGeneratingHeadline: String { avatar("正在画你", "Drawing you.") }
    static var avatarGeneratingSubtitle: String { avatar("几秒钟。", "A few seconds.") }

    static var avatarConfirmHeadline: String { avatar("这是你", "Done. This is you.") }
    static var avatarConfirm: String { avatar("就是这样", "That's me") }
    static var avatarRedraw: String { avatar("重画一张", "Draw another") }
    static var avatarNewPhoto: String { avatar("换张照片", "Use another photo") }
    static var avatarUseMemoji: String { avatar("用我的 Memoji", "Use my Memoji") }
    static var avatarMakeEmoji: String { avatar("做成 emoji", "Make an emoji") }
    static var avatarMemojiHint: String {
        avatar("在表情键盘里点一个你的 Memoji 贴纸", "Tap one of your Memoji stickers on the emoji keyboard")
    }
    static var avatarMemojiSteps: [String] {
        [
            avatar("点下面的输入框，再点键盘左下角的 😊 切到表情键盘",
                   "Tap the box below, then 😊 at the bottom left of the keyboard"),
            avatar("在表情那一排往右滑到最左边，「常用」左边就是贴纸，你的 Memoji 在那里",
                   "Swipe the emoji right to the very start: your Memoji stickers are left of Frequently Used"),
            avatar("点一个 Memoji，它就是你的头像",
                   "Tap a Memoji and it becomes your avatar"),
        ]
    }
    static var avatarMemojiNone: String {
        avatar("看不到 Memoji？先去「设置 ▸ 通用 ▸ 键盘」打开「拟我表情贴纸」。还没捏过：打开「信息」，进任意对话，点 ＋ ▸ 贴纸 ▸ 拟我表情，捏一个再回来。",
               "No Memoji? Turn on Memoji Stickers in Settings ▸ General ▸ Keyboard. None made yet: open Messages, any chat, ＋ ▸ Stickers ▸ Memoji, make one and come back.")
    }
    static var avatarHistory: String { avatar("或者用回以前的头像", "Or use an earlier one") }
    static var avatarUseEarlier: String { avatar("用这个以前的头像", "Use this earlier avatar") }
    static var avatarApplePlayground: String { avatar("让苹果画一张", "Let Apple draw it") }
    static var avatarDone: String { avatar("好了，去记今天。", "All set. Go film today.") }
    static var avatarAccessibility: String { avatar("你的头像", "Your avatar") }
    static var avatarUseBuddy: String { avatar("用这个小人", "Use this buddy") }
    static var avatarOrBuddy: String { avatar("不想用照片？选一个", "Rather not use a photo? Pick one") }

    static var avatarRedoHint: String { avatar("点一下重画头像", "Tap to redraw your avatar") }

    static func memberMoodAccessibility(name: String, mood: String) -> String {
        avatar("\(name)，今天\(mood)", "\(name), feeling \(mood.lowercased()) today")
    }
}
