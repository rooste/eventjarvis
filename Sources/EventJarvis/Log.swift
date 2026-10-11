import Foundation
import os

enum Log {
    private static let logger = Logger(subsystem: "com.juujarvis.eventjarvis", category: "bridge")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    nonisolated(unsafe) private static var fileHandle: FileHandle?

    static func configure(logFile: String) {
        let dir = (logFile as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: logFile) {
            FileManager.default.createFile(atPath: logFile, contents: nil)
        }

        fileHandle = FileHandle(forWritingAtPath: logFile)
        fileHandle?.seekToEndOfFile()
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        emit("INFO", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        emit("ERROR", message)
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        emit("DEBUG", message)
    }

    static func warn(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        emit("WARN", message)
    }

    private static func emit(_ level: String, _ message: String) {
        let ts = dateFormatter.string(from: Date())
        let line = Data("\(ts) [\(level)] \(message)\n".utf8)
        FileHandle.standardError.write(line)
        fileHandle?.write(line)
    }
}
