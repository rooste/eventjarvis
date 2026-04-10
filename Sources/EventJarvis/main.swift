import Foundation

@MainActor
func processNewMessages(
    poller: MessagePoller,
    watermark: WatermarkStore,
    client: JuujarvisClient,
    attachmentProcessor: AttachmentProcessor,
    lastRowId: inout Int64
) {
    let (messages, newMaxRowId) = poller.poll(since: lastRowId)
    guard !messages.isEmpty else { return }

    Log.info("Found \(messages.count) new message(s)")

    for (raw, rawAttachments) in messages {
        let text = MessagePoller.resolveText(raw)
        let timestamp = MessagePoller.convertAppleDate(raw.date)

        // Build conversation
        var conversation: InboundConversation? = nil
        if let chatId = raw.chatIdentifier {
            let isGroup = raw.style == 43
            let participants = isGroup ? poller.fetchParticipants(chatIdentifier: chatId) : []
            conversation = InboundConversation(
                chatId: chatId,
                chatGuid: raw.chatGuid,
                isGroup: isGroup,
                displayName: raw.displayName,
                participants: participants.isEmpty ? nil : participants
            )
        }

        // Process attachments
        let attachments = rawAttachments.isEmpty
            ? nil
            : attachmentProcessor.process(rawAttachments, isAudioMessage: raw.isAudioMessage)

        // Append audio transcriptions to message text
        var finalText = text
        if let attachments {
            for att in attachments where att.type == AttachmentType.audio.rawValue {
                if let transcription = att.transcription, !transcription.isEmpty {
                    if finalText.isEmpty {
                        finalText = transcription
                    } else {
                        finalText += "\n\n[Audio transcription]: \(transcription)"
                    }
                }
            }
        }

        let message = InboundMessage(
            channel: "IMESSAGE",
            sender: raw.handleId,
            text: finalText,
            timestamp: timestamp,
            conversation: conversation,
            attachments: attachments
        )

        Log.info("Processing message from \(raw.handleId): \(finalText.prefix(80))")

        Task {
            await client.send(message)
        }
    }

    lastRowId = newMaxRowId
    watermark.write(lastRowId)
}

// MARK: - Bootstrap

let config = Config()
let poller = MessagePoller(dbPath: config.chatDBPath)
let watermark = WatermarkStore(filePath: config.watermarkFile)
let client = JuujarvisClient(baseURL: config.apiURL)
let attachmentProcessor = AttachmentProcessor(
    whisperBin: config.whisperBin, whisperModel: config.whisperModel)

// Initialize watermark: if no stored value, start from current max (skip history)
var lastRowId = watermark.read()
if lastRowId == 0 {
    lastRowId = poller.currentMaxRowId()
    watermark.write(lastRowId)
    Log.info("Initialized watermark at rowid \(lastRowId)")
}

Log.info("eventjarvis starting — watching \(config.chatDBPath)")
Log.info("API target: \(config.apiURL)")

// Initial poll to catch up
processNewMessages(
    poller: poller, watermark: watermark, client: client,
    attachmentProcessor: attachmentProcessor, lastRowId: &lastRowId)

// Set up FSEvents watcher
let watcher = ChatDBWatcher(chatDBPath: config.chatDBPath) {
    processNewMessages(
        poller: poller, watermark: watermark, client: client,
        attachmentProcessor: attachmentProcessor, lastRowId: &lastRowId)
}
watcher.start()

// Handle SIGINT/SIGTERM for clean shutdown
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler {
    Log.info("Received SIGINT — shutting down")
    watcher.stop()
    exit(0)
}
sigintSource.resume()
signal(SIGINT, SIG_IGN)

let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler {
    Log.info("Received SIGTERM — shutting down")
    watcher.stop()
    exit(0)
}
sigtermSource.resume()
signal(SIGTERM, SIG_IGN)

// Keep the process alive
RunLoop.main.run()
