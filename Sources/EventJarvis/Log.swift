import Foundation
import os

enum Log {
    private static let logger = Logger(subsystem: "com.juujarvis.eventjarvis", category: "bridge")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        stderr("INFO", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        stderr("ERROR", message)
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        stderr("DEBUG", message)
    }

    static func warn(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        stderr("WARN", message)
    }

    private static func stderr(_ level: String, _ message: String) {
        let ts = dateFormatter.string(from: Date())
        FileHandle.standardError.write(Data("\(ts) [\(level)] \(message)\n".utf8))
    }
}
