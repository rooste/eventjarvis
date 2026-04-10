import Foundation
import SQLite3

/// Raw message data extracted from chat.db before processing.
struct RawMessage {
    let rowid: Int64
    let text: String?
    let attributedBody: Data?
    let date: Int64
    let hasAttachments: Bool
    let isAudioMessage: Bool
    let handleId: String
    let chatIdentifier: String?
    let chatGuid: String?
    let displayName: String?
    let style: Int32
}

/// Attachment metadata from the attachment table.
struct RawAttachment {
    let filename: String?
    let mimeType: String?
    let transferName: String?
    let uti: String?
}

final class MessagePoller {
    private let dbPath: String

    /// Apple epoch: 2001-01-01 00:00:00 UTC in Unix time
    private static let appleEpochOffset: Double = 978307200.0

    private static let messagesQuery = """
        SELECT m.rowid, m.text, m.date, m.attributedBody,
               m.cache_has_attachments, m.is_audio_message,
               COALESCE(h.id, 'unknown') AS handle_id,
               c.chat_identifier, c.guid AS chat_guid, c.display_name, c.style
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.rowid
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.rowid
        LEFT JOIN chat c ON c.rowid = cmj.chat_id
        WHERE m.rowid > ?
          AND m.is_from_me = 0
        ORDER BY m.rowid ASC
        """

    private static let participantsQuery = """
        SELECT h.id FROM handle h
        JOIN chat_handle_join chj ON chj.handle_id = h.rowid
        JOIN chat c ON c.rowid = chj.chat_id
        WHERE c.chat_identifier = ?
        """

    private static let attachmentsQuery = """
        SELECT a.filename, a.mime_type, a.transfer_name, a.uti
        FROM attachment a
        JOIN message_attachment_join maj ON maj.attachment_id = a.rowid
        WHERE maj.message_id = ?
        """

    init(dbPath: String) {
        self.dbPath = dbPath
    }

    /// Poll for new messages since the given rowid. Returns parsed messages and the new max rowid.
    func poll(since lastRowId: Int64) -> (messages: [(RawMessage, [RawAttachment])], maxRowId: Int64) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let err = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Log.error("Failed to open chat.db: \(err)")
            if let db { sqlite3_close(db) }
            return ([], lastRowId)
        }
        defer { sqlite3_close(db) }

        sqlite3_busy_timeout(db, 5000)

        var results: [(RawMessage, [RawAttachment])] = []
        var maxRowId = lastRowId

        // Query new messages
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.messagesQuery, -1, &stmt, nil) == SQLITE_OK else {
            Log.error("Failed to prepare messages query: \(String(cString: sqlite3_errmsg(db!)))")
            return ([], lastRowId)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, lastRowId)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            let text = columnText(stmt, 1)
            let attributedBody = columnBlob(stmt, 3)
            let date = sqlite3_column_int64(stmt, 2)
            let hasAttachments = sqlite3_column_int(stmt, 4) != 0
            let isAudioMessage = sqlite3_column_int(stmt, 5) != 0
            let handleId = columnText(stmt, 6) ?? "unknown"
            let chatIdentifier = columnText(stmt, 7)
            let chatGuid = columnText(stmt, 8)
            let displayName = columnText(stmt, 9)
            let style = sqlite3_column_int(stmt, 10)

            let raw = RawMessage(
                rowid: rowid, text: text, attributedBody: attributedBody,
                date: date, hasAttachments: hasAttachments, isAudioMessage: isAudioMessage,
                handleId: handleId, chatIdentifier: chatIdentifier,
                chatGuid: chatGuid, displayName: displayName, style: style
            )

            let attachments = hasAttachments ? fetchAttachments(db: db!, messageRowid: rowid) : []
            results.append((raw, attachments))
            maxRowId = max(maxRowId, rowid)
        }

        return (results, maxRowId)
    }

    /// Fetch participants for a group chat.
    func fetchParticipants(chatIdentifier: String) -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.participantsQuery, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, chatIdentifier, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var participants: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let id = columnText(stmt, 0) {
                participants.append(id)
            }
        }
        return participants
    }

    /// Get the current max rowid in the message table (for initial watermark).
    func currentMaxRowId() -> Int64 {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(rowid) FROM message", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return 0
    }

    /// Convert Apple date (nanoseconds or seconds since 2001-01-01) to ISO 8601 string.
    static func convertAppleDate(_ value: Int64) -> String {
        // Modern macOS stores nanoseconds; detect by magnitude
        let seconds: Double
        if value > 1_000_000_000_000 {
            seconds = Double(value) / 1_000_000_000.0
        } else {
            seconds = Double(value)
        }
        let date = Date(timeIntervalSince1970: seconds + appleEpochOffset)
        return ISO8601DateFormatter().string(from: date)
    }

    /// Resolve message text: prefer m.text, fall back to attributedBody parsing.
    static func resolveText(_ raw: RawMessage) -> String {
        if let text = raw.text, !text.isEmpty {
            return text
        }
        if let body = raw.attributedBody, let parsed = AttributedBodyParser.extractText(from: body) {
            return parsed
        }
        return ""
    }

    // MARK: - Private

    private func fetchAttachments(db: OpaquePointer, messageRowid: Int64) -> [RawAttachment] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.attachmentsQuery, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, messageRowid)

        var attachments: [RawAttachment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            attachments.append(RawAttachment(
                filename: columnText(stmt, 0),
                mimeType: columnText(stmt, 1),
                transferName: columnText(stmt, 2),
                uti: columnText(stmt, 3)
            ))
        }
        return attachments
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard let ptr = sqlite3_column_blob(stmt, index) else { return nil }
        let len = sqlite3_column_bytes(stmt, index)
        guard len > 0 else { return nil }
        return Data(bytes: ptr, count: Int(len))
    }
}
