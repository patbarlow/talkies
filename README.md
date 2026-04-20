# Yap

A push-to-talk dictation app for macOS. Hold a hotkey, speak, release — cleaned-up text is pasted into whatever you're focused on.

Rough feature parity with Superwhisper / Wispr Flow, minus the polish. BYO API keys — nothing leaves your Mac except the audio sent to Groq for transcription (and optionally a short text prompt to Anthropic for cleanup).

## Stack

| Layer | Choice | Why |
|---|---|---|
| Transcription | Groq `whisper-large-v3-turbo` | ~200–400 ms for push-to-talk batch; ~$0.04/hr; good English quality |
| Cleanup (optional) | Anthropic `claude-haiku-4-5` | Best at the constrained "rewrite but don't embellish" task; fractions of a cent per utterance |
| Hotkey | `CGEventTap` (keys + modifier-only) | Works in every app, can swallow the key; handles Right ⌘ / fn / etc. |
| Insertion | Clipboard + synthesized ⌘V | Works in Electron apps where Accessibility insertion fails |
| Keys | macOS Keychain (`app.yap.Yap`) | Never touches disk in plaintext |
| Library | JSON at `~/Library/Application Support/Yap/library.json` | Simple, inspectable, encrypts at rest via FileVault |

Swap the transcription provider by editing `Sources/Yap/Transcriber.swift`; same for cleanup in `Cleaner.swift`.

## Build

Requirements: macOS 14+, Xcode command-line tools.

```bash
./Scripts/bundle.sh
open build/Yap.app
```

Ad-hoc signing by default. For distribution, swap the signing identity in `bundle.sh` to a Developer ID and pipe through `xcrun notarytool`.

On first launch Yap opens Settings → Permissions. Grant Microphone and Accessibility. Accessibility is required for the global hotkey and for synthesizing ⌘V — without it nothing works.

## Configure

Menu-bar mic icon → **Settings…**:

- **Home** — live stats (words this week, total, average WPM)
- **Library** — searchable history of every transcription, grouped by date
- **Hotkey** — click to rebind. Supports regular keys (F5, letters, …) and modifier-only bindings (Right ⌘, fn, …). Default is Right ⌘.
- **Cleanup** — toggle the Haiku post-processing pass
- **Vocabulary** — personal dictionary, passed to Whisper as a prompt
- **Permissions** — mic + accessibility, with live status polling
- **API Keys** — Groq (required), Anthropic (optional for cleanup)

## Use

Hold your push-to-talk key. A black pill appears near the top of the screen with a live mic-reactive waveform. Release → pill shows 3 pulsing dots while Groq transcribes → text is pasted into the frontmost app and the pill fades out.

Pressing any other key while holding a modifier-only hotkey cancels the recording — so real shortcuts like Right ⌘ + C still work.

## Architecture

- Menu-bar-only by default (`LSUIElement=YES`)
- Opening Settings flips `NSApp.setActivationPolicy(.regular)` — Dock icon + menu bar appear while configuring, disappear on close
- Floating recording pill is a borderless `NSPanel` at shielding-window level, positioned below the menu bar across all spaces
- Live waveform: 5-slot ring of normalized RMS from the `AVAudioEngine` tap, pushed to `AudioLevels.shared` from the audio thread
- Hotkey tap re-enables itself on `tapDisabledByTimeout` / `tapDisabledByUserInput` and auto-retries if Accessibility isn't granted at launch

## Files

```
Package.swift
Sources/Yap/
  Entry.swift               # NSApplication entry point
  AppDelegate.swift         # Menu bar, pipeline, settings window, activation policy
  Hotkey.swift              # CGEventTap (keys + modifier-only)
  HotkeyRecorder.swift      # SwiftUI hotkey picker
  Recorder.swift            # AVAudioEngine → WAV + RMS tap
  AudioLevels.swift         # Shared audio-level store for the pill
  FloatingOverlay.swift     # Borderless NSPanel pill (recording/processing)
  Transcriber.swift         # Groq Whisper client
  Cleaner.swift             # Anthropic Haiku cleanup
  Paster.swift              # Clipboard + synthesized ⌘V
  Library.swift             # Transcription history store (JSON)
  LibraryPane.swift         # SwiftUI library view
  Stats.swift               # Words / WPM / time aggregates
  PermissionsPane.swift     # Mic + Accessibility UX
  Settings.swift            # Keychain + UserDefaults
  SettingsView.swift        # Sidebar + routed panes
  IconTile.swift            # Gradient tile icons
  AboutPane.swift           # App info pane
Resources/
  Info.plist
  Yap.entitlements      # Mic + network. Not sandboxed (needed for cross-app events).
Scripts/
  bundle.sh                 # swift build → .app → codesign
```

## Deliberate omissions

- **Modes / per-app presets** — Superwhisper's Voice / Message / Email modes. Would be a map of bundle IDs → system-prompt overrides.
- **Streaming partials** — only useful if you add a "dictation session" mode; push-to-talk doesn't benefit.
- **Apple SpeechAnalyzer fallback** — free, on-device. Add as an alternate `Transcriber` for offline use.
- **Sync across devices** — library stays local. CloudKit would be the path for multi-Mac sync without a backend.
- **Licensing / paid tier** — none. BYO keys, local-first, free.
