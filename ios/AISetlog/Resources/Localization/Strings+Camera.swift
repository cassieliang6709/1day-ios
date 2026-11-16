import Foundation

extension Strings {
    static var filmMayContinueInBackground: String {
        AppLanguage.effective.resolved == .chinese ? "可以切换到其他应用，影片会继续生成。" : "You can use another app while your film is created."
    }

    static var filmKeepOpen: String {
        AppLanguage.effective.resolved == .chinese ? "请保持 1Day 在前台，等待影片生成。" : "Keep 1Day open while your film is created."
    }
    static var captureImportFailed: String {
        AppLanguage.effective.resolved == .chinese
            ? "片段尚未导入，请重试。原文件已保留。"
            : "Your clip hasn't been imported. The original is kept. Please retry."
    }
    static var backgroundFilmTitle: String {
        AppLanguage.effective.resolved == .chinese ? "正在生成影片" : "Creating your film"
    }

    static var backgroundFilmPreparing: String {
        AppLanguage.effective.resolved == .chinese ? "正在准备片段" : "Preparing clips"
    }

    static var stopRecording: String {
        AppLanguage.effective.resolved == .chinese ? "结束录制" : "Stop recording"
    }

    static var tapToFilmTwoSeconds: String {
        AppLanguage.effective.resolved == .chinese ? "点一下，拍 2 秒" : "Tap to film 2s"
    }
}
