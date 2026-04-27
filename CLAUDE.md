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

Run the release script from the repo root with the next version number:

```bash
./Scripts/release.sh 0.2.0
```

The script (fully automated, ~3 min):
1. Bumps `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist`
2. Builds a release binary and assembles `build/Yap.app` via `Scripts/bundle.sh`
3. Signs with Developer ID (Pat Barlow, T544U3WVL6)
4. Notarizes the zip with Apple, staples the ticket, re-zips
5. Builds a drag-to-Applications DMG, notarizes + staples that too
6. Signs the zip with Sparkle's EdDSA key (private key in keychain)
7. Prepends an `<item>` to `docs/appcast.xml` for the Sparkle update feed
8. Commits `Info.plist` + `appcast.xml`, tags `v<version>`, pushes
9. Creates a GitHub release and uploads the zip + DMG

**Prerequisites (already configured on this machine):**
- Notarytool keychain profile: `yap-notary`
- Developer ID cert in keychain
- Sparkle EdDSA private key in keychain (generated via `bin/generate_keys`)
- `gh` CLI authenticated
- `swift build` run at least once (puts `sign_update` in `.build/artifacts`)

**Version conventions:** use semantic versioning. Patch (0.1.x) for bug fixes and small tweaks; minor (0.x.0) for new user-facing features.

## Installed app vs dev
The installed release app and the debug binary coexist without conflict — different paths, no shared process state. Changes and testing on a branch never affect the installed version.
