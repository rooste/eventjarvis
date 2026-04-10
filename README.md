# eventjarvis

iMessage bridge for [Juujarvis](https://github.com/rooste/juujarvis). Watches macOS `chat.db` for incoming messages via FSEvents, transcribes audio attachments with [whisper.cpp](https://github.com/ggerganov/whisper.cpp), and POSTs to the Juujarvis inbound API.

## Prerequisites

- macOS 14+
- Swift 6.0+
- [whisper-cpp](https://github.com/ggerganov/whisper.cpp) (for audio transcription)
- Full Disk Access granted to Terminal (System Settings → Privacy & Security → Full Disk Access)

```bash
brew install whisper-cpp
mkdir -p ~/.local/share/whisper
curl -L -o ~/.local/share/whisper/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

## Build & Run

```bash
swift build -c release
.build/release/eventjarvis
```

## Configuration

All settings via environment variables:

| Variable | Default | Description |
|---|---|---|
| `EVENTJARVIS_API_URL` | `http://localhost:8080` | Juujarvis base URL |
| `EVENTJARVIS_CHAT_DB` | `~/Library/Messages/chat.db` | Path to iMessage database |
| `EVENTJARVIS_WHISPER_BIN` | `whisper-cli` | whisper.cpp binary |
| `EVENTJARVIS_WHISPER_MODEL` | `~/.local/share/whisper/ggml-base.bin` | GGML model file |
| `EVENTJARVIS_WATERMARK_FILE` | `~/.eventjarvis-watermark` | Rowid persistence file |

## How It Works

1. FSEvents watches `~/Library/Messages/` for `chat.db` changes
2. New incoming messages are read via SQLite (read-only) using a rowid watermark
3. Audio attachments (`.caf`) are converted to `.wav` via `afconvert` and transcribed by `whisper-cli`
4. Each message is POST'd to `POST /api/inbound` as JSON matching the Juujarvis OpenAPI spec
