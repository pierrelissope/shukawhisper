# ShukaWhisper — Plan

A personal, Gemini-powered replacement for Wispr Flow on macOS. Only the features actually used:
dictation with AI cleanup, custom dictionary, per-app styles, and transforms.

---

## 1. Product scope (v1)

| Feature | Behaviour |
|---|---|
| **Dictation** | Hold `Fn` → speak → release → cleaned text is inserted at the cursor in any app. Double-tap `Fn` → hands-free lock; tap `Fn` again to finish. `Esc` cancels. |
| **Cleanup** | Filler words removed, self-corrections resolved ("3pm, no, 4pm" → "4pm"), punctuation, paragraphs, lists when spoken as lists. |
| **Languages** | Auto-detect, French ↔ English, including mid-sentence code-switching. Never translates unless asked. |
| **Dictionary** | Words/names/jargon (e.g. `Supabase`, `kubectl`, coworker names) sent as vocabulary hints to the transcriber *and* as spelling rules to the formatter. Optional "heard as → write as" replacements. |
| **Styles** | Categories: **Personal messages**, **Work messages**, **Email**, **AI prompts & code**, **Other** (+ user-created categories). Each category = a preset (Very casual / Casual / Formal / Excited) + free-text custom instructions + an optional writing sample. Apps (bundle ID) and websites (domain, e.g. `mail.google.com`) are mapped to categories; the mapping is editable. The category is picked automatically from the frontmost app / browser tab. |
| **Transforms** | Select text anywhere → press `⌥1…⌥9` → text is rewritten in place. Built-ins: `⌥1` Polish, `⌥2` Prompt Engineer (turns rough text into a well-structured LLM prompt), `⌥3` Translate to English. Slots 4–9 are custom (name + instructions + optional samples). `⌥0` = **Voice transform**: select text, hold `⌥0`, speak any instruction ("make this shorter", "reply politely declining"). Undo is just `⌘Z`. |
| **History & stats** | Every dictation stored locally: raw transcript, final text, app, category, duration, latency. Stats: words dictated, WPM, time saved, streak. Re-copy / retry from history. |

Out of scope for v1: sync, mobile, snippets, notes, meetings.

---

## 2. Models (Gemini API)

| Step | Model | Why |
|---|---|---|
| Speech → text (primary) | `gemini-3.5-transcribe-live` over WebSocket | Audio is streamed **while you speak**, so the transcript is ready ~instantly on release. ~2.6–4% WER, 85+ locales, code-switching, custom vocabulary. ≈ $0.009/min. |
| Speech → text (fallback) | `gemini-3.5-transcribe` (Interactions API, `mode: "smart"`) | Used if the live socket fails or for recordings > 10 min. ≈ $0.005/min. |
| Style + formatting | Fastest current Gemini Flash / Flash-Lite text model (exact ID resolved against `models.list` at build time) | Applies style category, custom instructions, dictionary spelling. Small prompt, ~200–400 ms. |
| Transforms | Same Flash model (or a larger Flash for Prompt Engineer) | Text-in / text-out rewrite. |

**Cost estimate**: 1 h of dictation / day ≈ **$0.30/day transcription + pennies for formatting ≈ $5–10/month worst case**, typically much less.

**Phase-1 bake-off**: I'll measure end-to-end latency and quality on real FR/EN samples for three pipelines and keep the winner (the code hides it behind a `Transcriber` protocol either way):
1. Live transcribe (streaming) → Flash formatter  ← expected winner
2. Batch transcribe `smart` → Flash formatter
3. Single multimodal Flash call (audio + style prompt → final text)

Target: **< 800 ms** from key release to text inserted for a typical 10 s utterance.

### Bake-off results (2026-09-29, FR / EN / mixed samples)

| Pipeline | Latency after key release | Quality |
|---|---|---|
| **Live `gemini-3.5-transcribe-live` (default mode, manual VAD) → `gemini-3.5-flash-lite` formatter** | **0.2–0.45 s + ~0.55 s** | Vocabulary respected, perfect FR/EN code-switching. ✅ **Chosen** |
| Live with `mode: SMART` | 0.2–0.3 s | ❌ Drops content (lost a whole English clause, rewrote meaning) |
| Batch Interactions API (`custom_vocabulary`) | 2.3–3.5 s | Accurate, too slow. Kept as fallback. |
| `generateContent` on `gemini-3.5-transcribe` | ~1 s | ❌ Ignores vocabulary ("superbase", "cubectal") |
| Single multimodal Flash call | 1–7 s | ❌ Hallucinations, leaked reasoning |

Transforms use `gemini-3.8-flash` (higher quality, latency less critical).

---

## 3. Technology

- **Native Swift 6 + SwiftUI + AppKit**, macOS 26 only. No Electron or Tauri: the app stays around 20 MB of RAM, starts instantly, and gets native Liquid Glass (`glassEffect`) and real system integration.
- **Swift Package Manager**, built with the command-line tools you already have (no Xcode). A `make` script builds, bundles and signs `ShukaWhisper.app` and installs it to `/Applications`.
- **Zero third-party dependencies** unless one clearly pays off. `URLSession` handles HTTP and WebSocket, `AVAudioEngine` handles audio, and Keychain stores the API key.
- **Code signing**: a local self-signed certificate is created once, so the Accessibility and Microphone permissions **survive rebuilds**. Ad-hoc signing resets them every build.

### System integration
| Need | API |
|---|---|
| Global `Fn` / `⌥n` hotkeys, `Esc` cancel | `CGEventTap` (flagsChanged + keyDown), needs Accessibility permission |
| Mic capture, 16 kHz mono PCM + level meter | `AVAudioEngine` + `AVAudioConverter` |
| Frontmost app | `NSWorkspace.frontmostApplication` |
| Browser URL (Gmail in Chrome ≠ "Other") | Accessibility `AXURL` of the focused web area; AppleScript fallback for Chrome/Arc/Safari |
| Read selected text (transforms) | `AXSelectedText`; fallback: synthesize `⌘C` and read the pasteboard |
| Insert text | Save pasteboard → write text → synthesize `⌘V` → restore pasteboard |
| Floating pill | Borderless, non-activating `NSPanel` hosting SwiftUI (never steals focus) |
| Menu bar | `MenuBarExtra` |

---

## 4. Architecture

```
┌──────────────────────────── ShukaWhisper.app ────────────────────────────┐
│                                                                           │
│  Input layer            Core (actor-isolated)               Output layer  │
│  ───────────            ─────────────────────               ────────────  │
│  HotkeyMonitor ──▶ DictationSession state machine ──▶ TextInserter        │
│  (CGEventTap)          idle → recording → locked                          │
│                        → transcribing → formatting                        │
│  AudioRecorder ──▶        → inserting → done/error      ──▶ PillController│
│  (PCM + levels)                 │                            (NSPanel UI) │
│                                 ▼                                         │
│  ContextProvider ──▶ StyleResolver ──▶ PromptBuilder                      │
│  (app, URL, selection)  (category+preset+instructions+dictionary)         │
│                                 │                                         │
│                                 ▼                                         │
│                     Gemini layer (protocols, mockable)                    │
│                     ├─ LiveTranscriber   (WebSocket)                      │
│                     ├─ BatchTranscriber  (Files + Interactions)           │
│                     └─ TextModel         (format / transform)             │
│                                                                           │
│  Persistence: Settings/Dictionary/Styles/Transforms → JSON in             │
│  ~/Library/Application Support/ShukaWhisper · History → SQLite ·          │
│  API key → Keychain                                                       │
│                                                                           │
│  UI: MenuBarExtra · Main window (Home/History · Dictionary · Styles ·     │
│      Transforms · Settings) · Onboarding (key + permissions)              │
└───────────────────────────────────────────────────────────────────────────┘
```

### Repo layout
```
Package.swift
Sources/
  ShukaWhisper/          app entry, AppDelegate, dependency wiring
  Core/                  DictationSession, TransformSession, StyleResolver, PromptBuilder, models
  Gemini/                LiveTranscriber, BatchTranscriber, TextModel, API types
  System/                HotkeyMonitor, AudioRecorder, ContextProvider, TextInserter, Permissions, Keychain
  Storage/               SettingsStore, HistoryStore (SQLite)
  UI/                    Pill/, MainWindow/, Onboarding/, DesignSystem/
Tests/CoreTests/         state machine, style resolution, prompt building, API parsing (mocked network)
scripts/                 build-app.sh, make-cert.sh, Info.plist, entitlements
Makefile                 make run | make install | make test
```

`Core` doesn't depend on AppKit, so all the logic is unit-tested without the UI or the network.

---

## 5. UI and motion

**Inspiration**: Wispr Flow's pill, Apple's Dynamic Island, Raycast (density, keyboard-first), Linear (calm typography), macOS 26 Liquid Glass.

**The pill** is the main surface and gets the most care:
- **Idle**: invisible, or optionally a tiny 6 px glass dot at the bottom-center.
- **Recording**: springs out from the dot (spring response 0.32 s, damping 0.78) into a glass capsule with 14 waveform bars driven by live mic RMS. Bars are smoothed (fast attack, slow release) so they feel alive, not jittery. A small app icon on the left shows which style will apply.
- **Locked (hands-free)**: the capsule widens and shows a timer plus stop and cancel buttons.
- **Processing**: the bars collapse into a soft travelling shimmer.
- **Done**: a brief checkmark morph, then the pill shrinks back to the dot.
- **Error**: a gentle horizontal shake, red tint, and a one-line reason ("No internet", "Mic denied").
- Respects *Reduce Motion* by swapping to crossfades.

**Main window**: sidebar plus content, SF Pro, generous whitespace, one accent color. The Styles page mirrors Wispr's category tabs with big selectable preset cards, a live "preview" sentence rendered in each style, an instructions field, and a drag-to-assign app list.

---

## 6. Implementation phases (autonomous)

1. **Skeleton**: SwiftPM package, app bundle script, signing cert, menu bar app launches, onboarding (API key → Keychain, Mic + Accessibility permissions).
2. **Gemini layer + bake-off**: resolve model IDs, implement live/batch transcribers + text model, CLI harness to benchmark the three pipelines on recorded FR/EN samples, then pick the winner.
3. **Dictation loop**: hotkeys (hold, double-tap lock, Esc), recorder, session state machine, formatter, insertion. End-to-end working in any app.
4. **Pill UI**: all states and animations.
5. **Dictionary + Styles**: data model, resolver (bundle ID + domain), prompts, main-window pages.
6. **Transforms**: selection capture, `⌥1–9` slots, built-ins, voice transform `⌥0`, Transforms page.
7. **History & stats**: SQLite store, Home page.
8. **Hardening**: unit tests, error states, offline handling, latency logging, launch-at-login, README.

Every phase ends with a build, tests, and a manual smoke test before moving on.

---

## 7. Notes and risks

- **Quit Wispr Flow** when using ShukaWhisper, since both listen to `Fn`. Also set *System Settings → Keyboard → "Press 🌐 key to" → Do Nothing*.
- The Gemini 3.5 Transcribe APIs are new. If the live endpoint misbehaves, batch transcription remains a working fallback (a bit slower).
- Pasteboard-based insertion is how Wispr does it too, and it works everywhere including terminals. The previous clipboard content is restored.
- Audio is sent only to Google's Gemini API. Nothing else leaves the machine, and history stays local.
