import Foundation

/// Copy for the 心情日记 card in 我的. Kept out of `Localization.swift` so
/// parallel edits don't collide.
extension Strings {
    static var moodSectionTitle: String { AppLanguage.effective.resolved == .chinese ? "今天的心情" : "Today's mood" }
    static var moodPrompt: String { AppLanguage.effective.resolved == .chinese ? "今天感觉怎么样？" : "How are you feeling today?" }
    static var moodNotePlaceholder: String { AppLanguage.effective.resolved == .chinese ? "写一句话（可选）" : "One line about today (optional)" }
    static var moodPrivateHint: String { AppLanguage.effective.resolved == .chinese ? "只有你自己看得到" : "Only you can see this" }

    static var moodHappy: String { AppLanguage.effective.resolved == .chinese ? "开心" : "Happy" }
    static var moodCalm: String { AppLanguage.effective.resolved == .chinese ? "平静" : "Calm" }
    static var moodTired: String { AppLanguage.effective.resolved == .chinese ? "累" : "Tired" }
    static var moodSad: String { AppLanguage.effective.resolved == .chinese ? "难过" : "Sad" }
    static var moodAngry: String { AppLanguage.effective.resolved == .chinese ? "生气" : "Angry" }

    private static func mood(_ zh: String, _ en: String) -> String {
        AppLanguage.effective.resolved == .chinese ? zh : en
    }

    // Saved state
    static var moodSaved: String { mood("今天记下了", "Saved for today") }
    static var moodEdit: String { mood("改", "Edit") }
    static var moodDone: String { mood("记下了", "Save") }
    static var moodEditFaceHint: String { mood("点一下改心情", "Tap to change") }

    // Dictation
    static var moodMicStart: String { mood("语音输入", "Dictate") }
    static var moodMicStop: String { mood("停止语音输入", "Stop dictation") }
    static var moodMicListening: String { mood("在听…再点一下停止", "Listening… tap again to stop") }
    static var moodMicDenied: String { mood("需要麦克风和语音识别权限才能语音输入", "Dictation needs mic and speech access") }
    static var moodMicUnavailable: String { mood("这会儿用不了语音输入", "Dictation isn't available right now") }
    static var moodOpenSettings: String { mood("去设置", "Settings") }

    // Mascot chat
    static var moodChatButton: String { mood("和小方块聊两句", "Chat with Little Cube") }
    static var moodChatTitle: String { mood("小方块", "Little Cube") }
    static var moodChatPlaceholder: String { mood("说点什么…", "Say something…") }
    static var moodChatSend: String { mood("发送", "Send") }
    static var moodChatClose: String { mood("完成", "Done") }
    static var moodChatFull: String { mood("今天先聊到这儿，明天见。", "That's it for today. See you tomorrow.") }
    static var moodChatFallback: String { mood("我这会儿连不上网，不过我在听。等会儿再聊？", "I can't reach the internet right now, but I'm listening. Try again in a bit?") }
    static var moodChatPrivate: String { mood("聊天只存在这台手机上", "This chat stays on this phone") }
}
