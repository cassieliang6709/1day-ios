import Foundation

/// Copy for the 朋友 tab's invite flow. Kept apart from `Localization.swift`
/// so the invite sheet's words live next to each other.
extension Strings {
    private static var zh: Bool { AppLanguage.effective.resolved == .chinese }

    static var inviteSheetTitle: String { zh ? "把邀请码发给朋友" : "Send the code to a friend" }
    static var inviteSheetBody: String {
        zh ? "朋友在 1Day 的「朋友 ▸ 加入」里输入这串码，就能进到这个房间。"
            : "Your friend enters this code under Friends ▸ Join to get into this room."
    }
    static var pickRoomTitle: String { zh ? "邀请朋友进哪个房间？" : "Which room to invite to?" }
    static var newRoomRow: String { zh ? "新建房间" : "New room" }
    static var copyCode: String { zh ? "复制邀请码" : "Copy code" }
    static var codeCopied: String { zh ? "已复制" : "Copied" }
    static var shareCode: String { zh ? "发给朋友" : "Share" }
    static func memberCount(_ n: Int) -> String { zh ? "\(n) 人" : (n == 1 ? "1 person" : "\(n) people") }
    static func inviteCodeLine(_ code: String) -> String { zh ? "邀请码 \(code)" : "Code \(code)" }

    static var signInRequiredTitle: String { zh ? "需要先登录" : "Sign in first" }

    #if DEBUG
    static var debugTestRoomFailedTitle: String { zh ? "测试房间没建成" : "Couldn't create test room" }
    static var debugSection: String { zh ? "调试" : "Debug" }
    static var debugCreateTestRoom: String { zh ? "创建测试房间" : "Create test room" }
    static var debugCreatingTestRoom: String { zh ? "正在创建测试房间…" : "Creating test room…" }
    static var debugTestRoomCaption: String {
        zh ? "在 CloudKit 开发环境建一个真房间（连正式库时不可用），放进小红和小明的假视频"
            : "Real room in the CloudKit development database, with fake clips from two friends (not on Production)"
    }
    static var debugTestRoomTitle: String { zh ? "测试房间" : "Test room" }
    static var debugTestRoomCreated: String { zh ? "测试房间已创建，在「朋友」里" : "Test room created — see Friends" }
    static var debugTestRoomNeedsSignIn: String {
        zh ? "需要先登录（上方头像处），才能创建测试房间。" : "Sign in first (at the top) to create a test room."
    }
    static var debugTestRoomNeedsDevelopment: String {
        zh ? "现在连的是正式库，不写假视频。要用这个按钮，先把 project.yml 里 Debug 的 CLOUDKIT_ENVIRONMENT 改成 Development。"
            : "This build uses the Production database, so no fake clips. Set Debug's CLOUDKIT_ENVIRONMENT to Development in project.yml first."
    }
    #endif
}
