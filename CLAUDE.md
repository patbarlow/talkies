# Talkies (Yap) — Dev Guide

## Project structure
Pure Swift Package Manager macOS app. No Xcode project. Menu bar dictation app that records audio, transcribes via API, and pastes the result.

## Dev workflow

### Making and testing changes
1. Create a branch for the work
2. Make changes
3. Build and run the debug binary:
   ```bash
   swift build
   .build/arm64-apple-macosx/debug/Yap
   ```
4. Test the changes, iterate as needed — each `swift build` overwrites the same binary, no accumulation

The debug binary is fully functional. The only thing that doesn't work is Sparkle (auto-updates), which doesn't matter for dev.

### Permissions on first debug run
- **Microphone** — grant once, persists (tracked by binary path, which doesn't change)
- **Accessibility** — needs re-granting in System Settings → Privacy & Security → Accessibility after each rebuild (macOS ties trust to binary hash). Remove and re-add the entry each time.
- **Keychain** — no prompt needed; debug binary reads the same session token as the release app (same service name, no code-signing restriction)

### Testing as a proper .app (optional)
If you need to test something that requires a real bundle (e.g. login items, bundle ID behavior):
```bash
SIGN_ID="-" ./Scripts/bundle.sh
open build/Yap.app
```
Ad-hoc signed, runs locally fine. `build/Yap.app` is gitignored and replaced on each run.

## Shipping a release

### PR and merge
1. Open a PR from the feature branch to `main`
2. Review and merge

### Creating a release
_(To be documented after first release cycle with this workflow)_

## Installed app vs dev
The installed release app and the debug binary coexist without conflict — different paths, no shared process state. Changes and testing on a branch never affect the installed version.
