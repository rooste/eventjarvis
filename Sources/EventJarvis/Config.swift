import Foundation

struct Config {
    let apiURL: URL
    let chatDBPath: String
    let whisperBin: String
    let whisperModel: String
    let watermarkFile: String
    let logFile: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        self.apiURL = URL(string: Self.env("EVENTJARVIS_API_URL", default: "http://localhost:8080"))!
        self.chatDBPath = Self.env("EVENTJARVIS_CHAT_DB", default: "\(home)/Library/Messages/chat.db")
        self.whisperBin = Self.env("EVENTJARVIS_WHISPER_BIN", default: "whisper-cli")
        self.whisperModel = Self.env("EVENTJARVIS_WHISPER_MODEL", default: "\(home)/.local/share/whisper/ggml-base.bin")
        self.watermarkFile = Self.env("EVENTJARVIS_WATERMARK_FILE", default: "\(home)/.eventjarvis-watermark")
        self.logFile = Self.env("EVENTJARVIS_LOG_FILE", default: "\(FileManager.default.currentDirectoryPath)/logs/eventjarvis.log")
    }

    private static func env(_ key: String, default defaultValue: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? defaultValue
    }
}
