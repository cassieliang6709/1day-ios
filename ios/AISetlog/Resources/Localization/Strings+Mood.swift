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
    static var moodChatButton: String { mood("和\(mascotName)聊两句", "Chat with \(mascotName)") }
    static var moodChatTitle: String { mascotName }
    /// The name the user gave the mascot, else 小方块.
    static var mascotName: String { MascotName.current ?? mood("小方块", "Little Cube") }
    /// 「和豆豆聊两句」 for a given stored name; empty means the default.
    static func chatButton(named name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? moodChatButton : mood("和\(trimmed)聊两句", "Chat with \(trimmed)")
    }
    static var mascotNameQuestion: String { mood("给它起个名字吧", "Give it a name") }
    static var mascotNameMessage: String {
        mood("它会用这个名字和你聊天。之后点标题可以再改。", "It'll go by this name when you chat. Tap the title to change it later.")
    }
    static var mascotNamePlaceholder: String { mood("比如：豆豆", "e.g. Mochi") }
    static var mascotNameSave: String { mood("就叫这个", "Save") }
    static var mascotNameSkip: String { mood("先不起", "Not now") }
    static var mascotRename: String { mood("改名字", "Rename") }
    static var moodChatPlaceholder: String { mood("说点什么…", "Say something…") }
    static var moodChatSend: String { mood("发送", "Send") }
    static var moodChatClose: String { mood("完成", "Done") }
    static var moodChatFull: String { mood("今天先聊到这儿，明天见。", "That's it for today. See you tomorrow.") }
    static var moodChatFallback: String { mood("我这会儿连不上网，不过我在听。等会儿再聊？", "I can't reach the internet right now, but I'm listening. Try again in a bit?") }
    static var moodChatPrivate: String { mood("聊天只存在这台手机上", "This chat stays on this phone") }
}

/// The mascot's nickname, kept on this phone. Nil until the user picks one.
enum MascotName {
    static let storageKey = "mascotName"
    /// Set once the name has been asked, so skipping isn't asked again.
    static let askedKey = "mascotNameAsked"
    static let maxLength = 12

    static var current: String? {
        let name = UserDefaults.standard.string(forKey: storageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    static func save(_ raw: String) {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        UserDefaults.standard.set(name, forKey: storageKey)
        UserDefaults.standard.set(true, forKey: askedKey)
    }
}
