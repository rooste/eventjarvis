import Foundation

struct WatermarkStore {
    let filePath: String

    func read() -> Int64 {
        guard let data = FileManager.default.contents(atPath: filePath),
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Int64(str) else {
            return 0
        }
        return value
    }

    func write(_ rowid: Int64) {
        do {
            try String(rowid).write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            Log.error("Failed to write watermark: \(error)")
        }
    }
}
