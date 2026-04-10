import Foundation

struct AttachmentProcessor {
    let whisperBin: String
    let whisperModel: String

    private static let tempDir = "/tmp/eventjarvis"

    /// Process raw attachments: classify type, transcribe audio if possible.
    func process(_ rawAttachments: [RawAttachment], isAudioMessage: Bool) -> [InboundAttachment] {
        rawAttachments.map { raw in
            let type = AttachmentType.from(mimeType: raw.mimeType, uti: raw.uti)
            let resolvedPath = resolvePath(raw.filename)

            var transcription: String? = nil
            if type == .audio || isAudioMessage, let path = resolvedPath {
                transcription = transcribeAudio(at: path)
            }

            return InboundAttachment(
                type: type.rawValue,
                mimeType: raw.mimeType,
                transcription: transcription,
                filename: raw.transferName ?? raw.filename.flatMap { URL(fileURLWithPath: $0).lastPathComponent },
                url: resolvedPath
            )
        }
    }

    /// Resolve a chat.db attachment path (replaces ~ with home directory).
    private func resolvePath(_ path: String?) -> String? {
        guard let path else { return nil }
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            Log.warn("Attachment file not found: \(expanded)")
            return nil
        }
        return expanded
    }

    /// Transcribe an audio file using whisper.cpp CLI.
    /// Converts .caf to .wav first using macOS afconvert.
    private func transcribeAudio(at path: String) -> String? {
        do {
            try FileManager.default.createDirectory(
                atPath: Self.tempDir, withIntermediateDirectories: true)
        } catch {
            Log.error("Failed to create temp dir: \(error)")
            return nil
        }

        let uuid = UUID().uuidString
        let wavPath = "\(Self.tempDir)/\(uuid).wav"
        defer { cleanup(wavPath) }

        // Convert to WAV using afconvert
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let inputPath: String
        if ext == "wav" {
            inputPath = path
        } else {
            guard runProcess("/usr/bin/afconvert", args: ["-f", "WAVE", "-d", "LEI16", path, wavPath]) else {
                Log.error("afconvert failed for \(path)")
                return nil
            }
            inputPath = wavPath
        }

        // Run whisper-cli with explicit output path
        let outputBase = "\(Self.tempDir)/\(uuid)-out"
        let txtPath = "\(outputBase).txt"
        defer { cleanup(txtPath) }

        guard runProcess(whisperBin, args: [
            "-m", whisperModel, "-f", inputPath,
            "--no-timestamps", "-otxt", "-of", outputBase
        ]) else {
            Log.error("whisper-cli failed for \(inputPath)")
            return nil
        }

        // Read transcription output
        guard let output = try? String(contentsOfFile: txtPath, encoding: .utf8) else {
            Log.error("Could not read whisper output: \(txtPath)")
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func runProcess(_ executable: String, args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable.hasPrefix("/") ? executable : "/usr/bin/env")
        if executable.hasPrefix("/") {
            process.arguments = args
        } else {
            process.arguments = [executable] + args
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            Log.error("Failed to run \(executable): \(error)")
            return false
        }
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
