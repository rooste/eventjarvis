import CoreServices
import Foundation

/// Watches the ~/Library/Messages/ directory for FSEvents and calls a handler
/// when chat.db (or its WAL/SHM files) changes.
/// Also runs a fallback timer poll every 5 seconds in case FSEvents misses events.
@MainActor
final class ChatDBWatcher {
    private var stream: FSEventStreamRef?
    private var fallbackTimer: Timer?
    private let directoryPath: String
    private let onChange: () -> Void
    private var lastPollTime: Date = .distantPast
    private static let debounceInterval: TimeInterval = 0.5

    init(chatDBPath: String, onChange: @escaping () -> Void) {
        self.directoryPath = (chatDBPath as NSString).deletingLastPathComponent
        self.onChange = onChange
    }

    func start() {
        startFSEvents()
        startFallbackTimer()
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        Log.info("Stopped watching chat.db")
    }

    private func startFSEvents() {
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
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
        Log.info("Watching \(directoryPath) for chat.db changes (FSEvents)")
    }

    private func startFallbackTimer() {
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleChange()
            }
        }
        RunLoop.main.add(timer, forMode: .default)
        fallbackTimer = timer
        Log.info("Fallback poll timer started (5s interval)")
    }

    private func handleChange() {
        let now = Date()
        guard now.timeIntervalSince(lastPollTime) >= Self.debounceInterval else { return }
        lastPollTime = now
        Log.debug("Polling for new messages")
        onChange()
    }
}
