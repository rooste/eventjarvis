import Foundation

struct InboundMessage: Codable {
    let channel: String
    let sender: String
    let text: String
    let timestamp: String?
    let conversation: InboundConversation?
    let attachments: [InboundAttachment]?
}

struct InboundConversation: Codable {
    let chatId: String
    let chatGuid: String?
    let isGroup: Bool?
    let displayName: String?
    let participants: [String]?
}

struct InboundAttachment: Codable {
    let type: String
    let mimeType: String?
    let transcription: String?
    let filename: String?
    let url: String?
}

struct InboundResponse: Codable {
    let status: String
}

enum AttachmentType: String {
    case audio = "AUDIO"
    case image = "IMAGE"
    case video = "VIDEO"
    case file = "FILE"

    static func from(mimeType: String?, uti: String?) -> AttachmentType {
        if let mime = mimeType {
            if mime.hasPrefix("audio/") { return .audio }
            if mime.hasPrefix("image/") { return .image }
            if mime.hasPrefix("video/") { return .video }
        }
        if let uti = uti {
            if uti.contains("audio") { return .audio }
            if uti.contains("image") { return .image }
            if uti.contains("video") { return .video }
        }
        return .file
    }
}
