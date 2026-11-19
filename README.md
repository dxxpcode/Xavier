# Xavier

A native macOS personal AI assistant. Local-first: inference runs entirely on
your machine via a local model runtime (Ollama today; MLX / llama.cpp later).
Conversations, memories, and settings stay on disk — nothing leaves the device.

## Features

- **Floating panel** — a compact, always-available conversation window that
  sits above other apps, auto-hides on inactivity, and expands on demand.
- **Menu bar presence** — open Xavier, start a voice conversation, jump to
  recent conversations, or quit from the status item.
- **Global hotkey** — Option+Space (rebindable) shows/hides the panel from
  anywhere.
- **Local inference** — chat is streamed from a local Ollama model. Models can
  be installed and removed from Preferences → AI Models.
- **Voice** — push-to-talk speech capture with on-device transcription and
  spoken replies, triggered from the mic button, menu bar, or ⌥M (all
  on-device; configurable in Preferences → Voice).
- **Persistent memory** — Xavier extracts durable facts, preferences, and
  goals from conversations with your consent, ranks them by relevance, and
  injects them into future context. Fully searchable and editable in
  Preferences → Memory.
- **Privacy** — SQLite storage in `~/Library/Application Support/Xavier`,
  per-conversation memory exclusion, sensitive-pattern filtering, one-click
  export and deletion.

## Requirements

- macOS 26 or later, Apple Silicon
- Xcode 26+
- [Ollama](https://ollama.com) running locally for inference
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you regenerate the
  project (`xcodegen`); the generated `Xavier.xcodeproj` is committed

## Build & run

```sh
xcodebuild -project Xavier.xcodeproj -scheme Xavier -configuration Debug build
open "$(xcodebuild -project Xavier.xcodeproj -scheme Xavier -showBuildSettings \
  | awk '/ BUILT_PRODUCTS_DIR/ {print $3}')/Xavier.app"
```

Or open `Xavier.xcodeproj` in Xcode and press ⌘R.

## Project layout

- `Sources/App` — app entry, delegate, shared state
- `Sources/Interface` — floating panel, menu bar, conversation UI, history,
  waveform, preferences, onboarding
- `Sources/Intelligence` — provider abstraction, Ollama client, model
  management, context builder, orchestration
- `Sources/Memory` — memory schema, extraction engine, retrieval
- `Sources/Persistence` — SQLite wrapper, stores, models
- `Sources/VoiceEngine` — capture, recognition, synthesis state machine
- `Sources/Support` — global hotkey (Carbon), logging
- `Sources/Security` — Keychain wrapper
- `tools/make_assets.swift` — regenerates brand assets from the official logos

## Regenerating assets

Place the official white-on-black and black-on-white logo files at
`/tmp/IMG_5780.png` and `/tmp/IMG_5607.png`, then:

```sh
swift tools/make_assets.swift
```
