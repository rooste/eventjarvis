import Foundation

enum AttributedBodyParser {
    /// Extract text from an NSArchiver attributedBody blob.
    /// Format: find "NSString" marker, then scan for 0x2B byte followed by
    /// a 1-byte length, then read that many UTF-8 bytes.
    static func extractText(from data: Data) -> String? {
        let marker: [UInt8] = Array("NSString".utf8)
        let bytes = Array(data)
        guard bytes.count > marker.count else { return nil }

        // Find "NSString" marker
        var markerIdx = -1
        outer: for i in 0...(bytes.count - marker.count) {
            for j in 0..<marker.count {
                if bytes[i + j] != marker[j] { continue outer }
            }
            markerIdx = i
            break
        }
        guard markerIdx >= 0 else { return nil }

        // Scan for 0x2B byte after the marker
        for i in (markerIdx + marker.count)..<(bytes.count - 1) {
            if bytes[i] == 0x2B {
                let len = Int(bytes[i + 1])
                if len > 0 && (i + 2 + len) <= bytes.count {
                    return String(bytes: Array(bytes[(i + 2)..<(i + 2 + len)]), encoding: .utf8)
                }
            }
        }
        return nil
    }
}
