# Talkies (Yap) — Dev Guide

## Project structure

Multi-platform voice dictation application. The macOS app is a pure Swift Package Manager project (no Xcode project file). A Cloudflare Workers TypeScript backend handles auth, transcription, and analytics. An iOS companion app with keyboard extension lives in `ios/`.

```
talkies/
├── Sources/Yap/        # macOS app (26 Swift files)
├── Resources/          # Info.plist, AppIcon.icns, entitlements, DMG background
├── Scripts/            # Build and release automation
├── talkies-api/        # Cloudflare Workers backend (TypeScript)
├── ios/                # iOS app + keyboard extension (xcodegen)
├── docs/               # appcast.xml (Sparkle update feed) + site assets
├── Package.swift       # SPM manifest: Yap executable, Sparkle 2.6.0+, macOS 14+
└── Package.resolved    # Dependency lock file
```

---

## macOS app

### Dev workflow

1. Create a branch for the work
2. Make changes
3. Build and run the debug binary:
   ```bash
   swift build
   .build/arm64-apple-macosx/debug/Yap
   ```
4. Test and iterate — each `swift build` overwrites the same binary, no accumulation

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

### Source files

**Core application:**

| File | Purpose |
|------|---------|
| `Entry.swift` | `@main` entry point; initializes `NSApplication` in accessory (menu-bar-only) mode |
| `AppDelegate.swift` | App lifecycle, menu bar item, hotkey installation, recording pipeline orchestration, Sparkle updater, `yap://` URL scheme handler |
| `Settings.swift` | User preferences (hotkey, cleanup level, language, vocabulary); Keychain session token storage; `CleanupLevel` and `TranscriptionLanguage` enums |
| `AuthStore.swift` | Auth state management; email magic-link flow (request code → verify); JWT session persistence; user data refresh |

**Recording & transcription:**

| File | Purpose |
|------|---------|
| `Recorder.swift` | `AVAudioEngine` wrapper; captures PCM audio to WAV; exposes RMS levels for UI |
| `AudioLevels.swift` | Real-time audio level calculation used by recording UI |
| `Transcriber.swift` | Calls backend `/v1/transcribe` with the recorded WAV; enforces session check |
| `Cleaner.swift` | Calls backend `/v1/cleanup` with transcript + app context for tone-aware cleanup |
| `Paster.swift` | Synthesizes ⌘V to paste text into the frontmost app; preserves clipboard contents after 300 ms |

**Data & sync:**

| File | Purpose |
|------|---------|
| `Library.swift` | Local transcript history; persists to `~/Library/Application Support/Yap/library.json`; max 5,000 entries; stores raw + final text, duration, app context |
| `Stats.swift` | Aggregated stats (total/week words, seconds, session count, WPM); Monday-based week tracking; persists to `UserDefaults` |
| `SessionSyncer.swift` | Batches unsynced library entries (200 at a time) and uploads to backend `/v1/sessions` |

**Hotkey:**

| File | Purpose |
|------|---------|
| `Hotkey.swift` | `CGEventTap`-based push-to-talk; handles regular keys and modifier-only combos; swallows the key event; cancels on other keypresses |
| `HotkeyRecorder.swift` | Interactive hotkey rebinding UI component |

**Networking:**

| File | Purpose |
|------|---------|
| `APIClient.swift` | HTTP client for all backend endpoints (auth, user, transcribe, cleanup, sessions, avatar, Stripe checkout) |

**UI (SwiftUI):**

| File | Purpose |
|------|---------|
| `SettingsView.swift` | Multi-pane settings window (Home, Library, Hotkey, Style, Account, Permissions, About) |
| `LibraryPane.swift` | Searchable, chronologically-grouped transcript history with copy/delete actions |
| `AccountPane.swift` | User profile, plan display, upgrade button, name editing |
| `SignInPane.swift` | Email + 6-digit code verification flow |
| `OnboardingView.swift` | First-run walkthrough |
| `PermissionsPane.swift` | Microphone + Accessibility permission prompts |
| `AboutPane.swift` | App info + links |
| `FloatingOverlay.swift` | Status overlays: recording indicator, processing spinner, limit-reached prompt, Claude Code review card |
| `ProfileImage.swift` | Avatar download and caching from server |
| `AppIconView.swift` | Menu bar icon rendering |
| `IconTile.swift` | Reusable icon button component |

### Key architecture patterns
- `@MainActor` throughout `AppDelegate` and all UI code
- Notifications (`NotificationCenter`) drive state transitions: `.yapAuthStateChanged`, `.yapAccessibilityChanged`, `.yapHotkeyChanged`
- `yap://record` deep-link triggers recording from external tools (e.g. Claude Code hook)
- `LSUIElement = true` — app lives only in the menu bar; no dock icon except when Settings window is open

### App metadata
- **Bundle ID:** `app.yap.Yap`
- **Current version:** 1.1.1 (build 96)
- **Minimum macOS:** 14.0
- **Sparkle feed:** `https://patbarlow.github.io/talkies/appcast.xml`

---

## Backend API (`talkies-api/`)

Cloudflare Workers app using the Hono framework, D1 SQLite database, and Resend for email.

### Dev setup
```bash
cd talkies-api
npm install
# Create .dev.vars with required secrets (see wrangler.toml for names)
npm run dev          # local Worker dev server
npm run db:migrate   # apply schema.sql to local D1
npm run db:migrate:remote  # apply to production D1
```

### Database schema (D1 SQLite)

**`users`** — accounts with plan and aggregate stats:
- `id`, `email` (unique), `name`, `plan` (`free`/`pro`)
- `week_words`, `total_words`, `session_count`, `week_start`
- `stripe_customer_id`, `stripe_subscription_id`

**`sessions`** — per-recording analytics:
- `user_id`, `recorded_at`, `word_count`, `duration_seconds`
- `app_name`, `bundle_id`, `cleanup_level`, `language`

**`email_codes`** — magic-link auth codes:
- `email` (primary key), `code_hash`, `attempts`, `expires_at`, `last_sent_at`
- Rate-limited: 30 s between sends, 10 min expiry

### API endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/auth/email/start` | — | Send 6-digit magic-link code via Resend |
| `POST` | `/auth/email/verify` | — | Verify code; returns HS256 JWT (365-day) |
| `GET` | `/v1/me` | ✓ | Current user profile + plan + stats |
| `PATCH` | `/v1/me` | ✓ | Update display name |
| `PUT` | `/v1/me/avatar` | ✓ | Upload avatar image |
| `GET` | `/v1/me/avatar` | ✓ | Fetch avatar image |
| `POST` | `/v1/transcribe` | ✓ | Transcribe audio via Groq Whisper; enforces 2,000-word/week free limit (402 when exceeded) |
| `POST` | `/v1/cleanup` | ✓ | Clean up transcript text via Claude Haiku with app-aware context |
| `POST` | `/v1/sessions` | ✓ | Ingest batch of session analytics records |
| `POST` | `/v1/stripe/checkout` | ✓ | Create Stripe checkout session for Pro plan |
| `POST` | `/v1/stripe/webhook` | — | Stripe webhook: update plan on subscription events |

### Key conventions
- Auth: Bearer JWT in `Authorization` header; validated by `src/middleware/auth.ts`
- Free tier limit: 2,000 words/week; resets Monday; `week_start` tracks current period
- `src/session.ts` — HS256 JWT, `jose` library, `JWT_SECRET` env var
- `src/email.ts` — code generation + hashing + Resend API call
- `src/db.ts` — D1 user queries + weekly word limit recomputation

---

## iOS app (`ios/`)

The iOS app and keyboard extension use xcodegen to generate `YapIOS.xcodeproj` from `ios/project.yml`. The xcodeproj is gitignored. Xcode Cloud runs `ios/ci_scripts/ci_post_clone.sh` on clone to generate it before building.

### Structure
```
ios/
├── project.yml         # xcodegen config — source of truth for build settings
├── YapIOS/             # Main app (App/, Auth/, IAP/, Profile/, Views/)
├── YapKeyboard/        # Keyboard extension
├── Shared/             # Code shared between app and extension
└── ci_scripts/ci_post_clone.sh  # Installs xcodegen, runs it
```

### Info.plist — critical gotcha
xcodegen **regenerates** both `ios/YapIOS/Info.plist` and `ios/YapKeyboard/Info.plist` from scratch when it runs. The files in git are effectively ignored during CI builds. **All required Info.plist keys must be declared in `ios/project.yml`** under each target's `info.properties` block — anything not listed there will be missing from the built binary and will fail App Store validation.

### iOS release
Xcode Cloud handles archiving and uploading to App Store Connect on every push to `main`.

### Local development
```bash
cd ios
xcodegen generate   # produces YapIOS.xcodeproj
open YapIOS.xcodeproj
```

---

## Scripts

| Script | Purpose |
|--------|---------|
| `Scripts/bundle.sh` | Assemble `build/Yap.app`: compile release binary, copy Info.plist + icon, embed Sparkle.framework from SPM artifacts, patch rpath, sign nested XPCs and the app |
| `Scripts/release.sh <version>` | Full release pipeline (see below) |
| `Scripts/make-dmg.sh` | Create DMG from a built app bundle |
| `Scripts/make-dmg-background.swift` | Generate DMG background PNG |
| `Scripts/make-icon.swift` | Generate `AppIcon.icns` from source |

---

## Shipping a release

### PR and merge
1. Open a PR from the feature branch to `main`
2. Review and merge

### Creating a release

Run the release script from the repo root:
```bash
./Scripts/release.sh 1.2.0
```

The script is fully automated (~3 min):
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

**Version conventions:** semantic versioning. Patch (1.x.y) for bug fixes and small tweaks; minor (x.y.0) for new user-facing features.

---

## Installed app vs dev

The installed release app and the debug binary coexist without conflict — different paths, no shared process state. Changes and testing on a branch never affect the installed version.
