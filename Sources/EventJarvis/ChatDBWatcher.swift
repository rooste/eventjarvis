import CoreServices
import Foundation

/// Watches the ~/Library/Messages/ directory for FSEvents and calls a handler
/// when chat.db (or its WAL/SHM files) changes.
final class ChatDBWatcher {
    private var stream: FSEventStreamRef?
    private let directoryPath: String
    private let onChange: () -> Void
    private var lastPollTime: Date = .distantPast
    private static let debounceInterval: TimeInterval = 0.5

    init(chatDBPath: String, onChange: @escaping () -> Void) {
        self.directoryPath = (chatDBPath as NSString).deletingLastPathComponent
        self.onChange = onChange
    }

    func start() {
        let pathsToWatch = [directoryPath] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<ChatDBWatcher>.fromOpaque(info).takeUnretainedValue()

            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            for i in 0..<numEvents {
                let path = unsafeBitCast(CFArrayGetValueAtIndex(paths, i), to: CFString.self) as String
                if path.contains("chat.db") {
                    watcher.handleChange()
                    return
                }
            }
        }

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            UInt64(kFSEventStreamEventIdSinceNow),
            1.0, // latency in seconds
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            Log.error("Failed to create FSEventStream")
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        Log.info("Watching \(directoryPath) for chat.db changes")
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        Log.info("Stopped watching chat.db")
    }

    private func handleChange() {
        let now = Date()
        guard now.timeIntervalSince(lastPollTime) >= Self.debounceInterval else { return }
        lastPollTime = now
        Log.debug("chat.db change detected")
        onChange()
    }
}
