# Architecture

ShukaWhisper is a menu bar app built with AppKit and SwiftUI on Swift 6 strict concurrency. It is split into three Swift Package Manager modules so that the logic can be tested without the UI or the network.

```
Sources/
  ShukaCore/        pure logic, no AppKit, no network          ← unit tested
    Models/         AppContext, StyleCategory, DictionaryEntry, Transform, AppSettings
    Styles/         StyleResolver: app / website → style category
    Prompts/        PromptBuilder: every prompt sent to a model
    Dictation/      PushToTalkGesture: hold / double-tap / cancel state machine
    Storage/        Configuration (JSON), HistoryStore (SQLite), UsageStats
  GeminiKit/        Gemini API clients, Foundation only           ← unit tested (network stubbed)
    LiveTranscription.swift   WebSocket streaming transcription (gemini-3.5-transcribe-live)
    BatchTranscriber.swift    one-shot transcription fallback (Interactions API)
    Transcriber.swift         live first, batch fallback, keeps the audio
    TextGenerator.swift       generateContent for cleanup and transforms
  ShukaWhisper/     the app
    App/            entry point, AppDelegate (menu bar, windows), AppModel (root state), dev commands
    Controllers/    SessionController: runs dictations and transforms end to end
    Services/       HotkeyMonitor, AudioRecorder, ContextProvider, TextInserter, APIKeyStore, Permissions
    UI/             Pill (floating indicator), Main (window pages), Onboarding, DesignSystem
```

## A dictation, step by step

1. **`HotkeyMonitor`** (a `CGEventTap`) sees `fn` go down and reports `.dictationKey(isDown: true)`.
2. **`SessionController`** passes it to **`PushToTalkGesture`**, which returns `[.startRecording]`. Recording starts on the first press so no speech is lost while the gesture (hold, tap or double-tap) is still unknown.
3. **`startRecording`** does the following at the same time:
   - snapshots the frontmost app, and starts an AppleScript lookup of the browser tab's host (**`ContextProvider`**);
   - opens the live transcription WebSocket (**`Transcriber`** → **`LiveTranscriptionSession`**);
   - pre-opens the HTTPS connection to the cleanup model (`TextGenerator.warmUp`);
   - starts **`AudioRecorder`**, which converts the mic input to 16 kHz mono PCM16. Chunks go through an `AsyncStream` (so order is kept) and are batched to about 100 ms before being sent. Audio sent before the socket is ready is buffered.
4. The pill shows a live waveform and the style category that will be used.
5. **Release**: the gesture returns `[.finish]`. The recorder stops and the session sends `activityEnd`. The server has been transcribing all along, so `generationComplete` arrives about 0.3 s later.
6. **`StyleResolver`** picks the category (website first, then bundle ID, then *Other*). **`PromptBuilder.dictation`** builds the cleanup prompt from the preset, custom instructions, writing sample and dictionary.
7. **`TextGenerator`** runs `gemini-3.5-flash-lite` (about 0.5 s). If that fails, the raw transcript is inserted instead, so a dictation is never lost.
8. **`TextInserter`** saves the pasteboard, writes the text (marked transient for clipboard managers), sends `⌘V`, and restores the pasteboard.
9. The entry is saved to **`HistoryStore`** and the pill shows ✓.

Transforms take the same path without steps 2–5: `⌥n` → read the selection (Accessibility API first, then a synthetic `⌘C`) → `PromptBuilder.transform` → `TextGenerator` → paste over the selection.

## Concurrency

- UI, controllers and `AppModel` are `@MainActor`. The event tap's run loop source is on the main run loop, so hotkey callbacks run on the main thread.
- `LiveTranscriptionSession`, `Transcriber` and `HistoryStore` are actors.
- The audio tap runs on a real-time thread. It only converts buffers and yields them to an `AsyncStream`, and sends levels to the main actor for the waveform.
- WebSocket messages use the callback-based `send`, so they are queued synchronously in call order even across actor suspension points.

## Key decisions

| Decision | Why |
|---|---|
| Native Swift, no Electron/Tauri | Instant startup, ~20 MB of memory, real Liquid Glass, direct access to system APIs. |
| Streaming transcription + separate cleanup model | Measured fastest and most accurate (see `PLAN.md`). The transcriber's built-in "smart" mode dropped content. |
| We run the cleanup, not the transcriber's "smart" mode | Control over the rules: never translate, never answer the dictated text, never drop content. |
| Paste via pasteboard + `⌘V` | Works in every app including terminals; typing character by character is slow and breaks on some layouts. |
| Record from the first key press | The gesture (hold vs tap vs double-tap) is only known later; starting late would cut off the first word. |
| JSON config + SQLite history | Config is human-readable and easy to back up; history needs search and aggregation. |
| No third-party dependencies | Easy to audit, nothing to update, builds with the Command Line Tools alone. |

## Testing

`make test` runs the unit tests for `ShukaCore` and `GeminiKit`: gesture state machine, style resolution, prompt building, storage, stats, protocol parsing and HTTP handling with a stubbed `URLProtocol`.

For end-to-end checks without the UI, `ShukaWhisper --transcribe file.wav` streams a WAV file at real-time speed through the real pipeline and prints the transcript, the final text and the latency. `ShukaWhisper --snapshots dir` renders every screen and pill state to PNG.
