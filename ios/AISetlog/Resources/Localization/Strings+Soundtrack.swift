import Foundation

/// Copy for the film's sound: music, the original-sound switch and voiceover.
extension Strings {
    private static func sound(_ zh: String, _ en: String) -> String {
        AppLanguage.effective.resolved == .chinese ? zh : en
    }

    static var soundTitle: String { sound("声音", "Sound") }
    static var soundOriginal: String { sound("原声", "Original") }
    static var soundMusic: String { sound("音乐", "Music") }
    static var soundMix: String { sound("混合", "Mix") }
    static var soundNextTrack: String { sound("换一首", "Next song") }
    static var soundWorking: String { sound("正在配声音…", "Mixing sound…") }
    static var soundFailed: String { sound("声音没配好，先放原声", "Couldn't mix the sound — playing the original") }
    static func soundTrackName(_ id: String) -> String {
        switch id {
        case "sunny": sound("晴天", "Sunny")
        case "spark": sound("火花", "Spark")
        case "breeze": sound("微风", "Breeze")
        case "drift": sound("慢慢", "Drift")
        case "rain": sound("下雨天", "Rainy day")
        default: sound("胶片", "Film")
        }
    }

    static var voiceoverAdd: String { sound("加旁白", "Add voiceover") }
    static var voiceoverRedo: String { sound("重录旁白", "Redo voiceover") }
    static var voiceoverRemove: String { sound("去掉旁白", "Remove voiceover") }
    static var voiceoverTitle: String { sound("边看边说", "Talk over your film") }
    static var voiceoverHint: String {
        sound("点开始，片子会从头播放，你说的话会录在片子上。播完自动停。",
              "Tap start: the film plays from the top and what you say is recorded over it. It stops at the end.")
    }
    static var voiceoverStart: String { sound("开始录", "Start") }
    static var voiceoverStop: String { sound("停", "Stop") }
    static var voiceoverRetake: String { sound("重录", "Retake") }
    static var voiceoverUse: String { sound("用这段", "Use this") }
    static var voiceoverRecording: String { sound("在录…", "Recording…") }
    static var voiceoverDenied: String { sound("需要麦克风权限才能录旁白", "Voiceover needs microphone access") }
}
