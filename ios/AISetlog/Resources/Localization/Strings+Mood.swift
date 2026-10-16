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
}
