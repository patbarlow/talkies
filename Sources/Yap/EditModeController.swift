import AppKit
import Carbon.HIToolbox
import Foundation

/// Drives "edit existing text" via voice. Triggered exclusively by the
/// optional second hotkey ("Edit clipboard"). The dictation hotkey is
/// always plain dictation.
///
/// Flow:
/// 1. User presses-and-holds the edit hotkey. We synthesize ⌘C to capture
///    whatever is selected in the frontmost app (works in Slack, Claude,
///    Chrome, anywhere). The original clipboard is restored.
/// 2. If nothing was selected, fall back to the most recent dictation
///    (within 60s) so the user can refine "the last thing I said".
/// 3. Recording bars + prompt card appear. User speaks the instruction and
///    releases.
/// 4. We transcribe → call /v1/edit → preview card with the draft.
/// 5. From preview: hold either hotkey to refine (history accumulates),
///    Return to apply, Esc to cancel.
@MainActor
final class EditModeController {
    static let shared = EditModeController()

    enum HotkeyKind { case dictate, edit }

    private enum State {
        case idle
        /// Edit hotkey was pressed; we're synthesizing ⌘C and waiting for
        /// the pasteboard to update. `stillHeld` tracks whether the user is
        /// still holding — if they release during the probe we abort.
        case probing(stillHeld: Bool)
        case recording(Session)
        case processing(Session)
        case previewing(Session)
    }

    /// How the source text was obtained — drives the writeback strategy on
    /// confirm.
    private enum Source {
        case clipboard(targetApp: NSRunningApplication?)
        case library
    }

    private final class Session {
        let originalText: String
        let source: Source
        var history: [APIClient.EditHistoryEntry]
        var draft: String?
        var recordingStartedAt: Date?

        init(text: String, source: Source) {
            self.originalText = text
            self.source = source
            self.history = []
        }
    }

    enum CancelReason {
        case userClosed
        case error(String)
    }

    private var state: State = .idle
    private let recorder = Recorder()

    private var refineHotkeyLabel: String {
        Settings.shared.editHotkey?.label
            ?? Settings.shared.hotkey?.label
            ?? "your shortcut"
    }

    // MARK: - Hotkey routing

    /// Called from AppDelegate on hotkey press. Returns true if edit mode
    /// handled it (so AppDelegate should NOT start its own dictation).
    func tryHandlePress(kind: HotkeyKind) -> Bool {
        switch state {
        case .idle:
            // The dictation hotkey is always pure dictation — fall through
            // and let AppDelegate.startRecording handle it.
            guard kind == .edit else { return false }
            // Edit mode is Pro-only. Free users get a toast pointing at
            // the upgrade rather than a confusing "nothing happens".
            guard AuthStore.shared.currentUser?.plan == "pro" else {
                FloatingOverlay.shared.show(.editToast(
                    message: "Edit mode is a Pro feature. Upgrade in Settings → Account."
                ))
                return true
            }
            state = .probing(stillHeld: true)
            Task { await runEditHotkeyProbe() }
            return true

        case .probing:
            // Stray re-press during probe; keep stillHeld true.
            state = .probing(stillHeld: true)
            return true

        case .previewing(let session):
            // Either hotkey can refine an in-progress edit. This is
            // intentional: pressing the dictation hotkey by accident here
            // shouldn't lose the user's draft.
            beginRecording(session: session, prompt: "What would you like to change?")
            return true

        case .recording, .processing:
            return true
        }
    }

    /// Called from AppDelegate on hotkey release. Returns true if edit mode
    /// handled it.
    func tryHandleRelease() -> Bool {
        switch state {
        case .probing:
            state = .probing(stillHeld: false)
            return true
        case .recording(let session):
            Task { await stopAndProcess(session: session) }
            return true
        default:
            return false
        }
    }

    /// Called from AppDelegate when the hotkey session is cancelled mid-hold
    /// (e.g. another key pressed while holding the modifier).
    func tryHandleCancel() -> Bool {
        switch state {
        case .probing:
            state = .probing(stillHeld: false)
            return true
        case .recording(let session):
            if let url = recorder.stop() {
                try? FileManager.default.removeItem(at: url)
            }
            // If we have a prior draft, return to preview; otherwise abort.
            if session.draft != nil {
                state = .previewing(session)
                FloatingOverlay.shared.show(.editPreview(
                    original: session.originalText,
                    draft: session.draft ?? "",
                    hotkeyLabel: refineHotkeyLabel
                ))
            } else {
                cancel(reason: .userClosed)
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Overlay actions

    /// Called from the overlay's Apply button (or Return key).
    ///
    /// Confirm policy is: **always copy the draft to the clipboard, never
    /// auto-restore**. Then, *only* if the source app is still the frontmost
    /// app, also synthesize ⌘V to replace the user's selection in place.
    /// This keeps the result accessible via clipboard regardless, and avoids
    /// blindly pasting into wherever focus might have wandered.
    func confirm() {
        guard case .previewing(let session) = state, let draft = session.draft else { return }
        state = .idle

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft, forType: .string)

        switch session.source {
        case .clipboard(let targetApp):
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let stillFrontmost = targetApp != nil && frontPID == targetApp?.processIdentifier
            if stillFrontmost {
                // Source app is still the active one — paste back into it.
                // Our overlay panel is `nonactivating` so the source app's
                // text view is still the first responder there.
                Self.synthesizeCommandV()
                FloatingOverlay.shared.show(.editToast(
                    message: "Replaced — also on clipboard."
                ))
            } else {
                FloatingOverlay.shared.show(.editToast(
                    message: "Edited — paste with ⌘V."
                ))
            }

        case .library:
            // No destination context — leave on clipboard for the user to
            // paste wherever they want.
            FloatingOverlay.shared.show(.editToast(
                message: "Edited — paste with ⌘V."
            ))
        }
    }

    private static func synthesizeCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Called from the overlay's close button or Esc key.
    func cancel(reason: CancelReason) {
        if case .recording = state, let url = recorder.stop() {
            try? FileManager.default.removeItem(at: url)
        }
        state = .idle
        switch reason {
        case .userClosed:
            FloatingOverlay.shared.show(.hidden)
        case .error(let message):
            FloatingOverlay.shared.show(.editToast(message: message))
        }
    }

    // MARK: - Internal flow

    private func runEditHotkeyProbe() async {
        let snapshot = await ClipboardProbe.probe()

        // Only proceed if we're still in probing state and the user is
        // still holding the key. Anything else means they cancelled or
        // pressed/released too fast.
        guard case .probing(let stillHeld) = state else { return }
        guard stillHeld else {
            state = .idle
            return
        }

        if let copied = snapshot.copiedText {
            let session = Session(
                text: copied,
                source: .clipboard(targetApp: snapshot.app)
            )
            beginRecording(session: session, prompt: "What would you like to do?")
            return
        }

        // No selection. Try the most recent dictation as a fallback.
        if let recent = Library.shared.mostRecentEntry(within: 60) {
            let session = Session(
                text: recent.finalText,
                source: .library
            )
            beginRecording(session: session, prompt: "What would you like to change about your last dictation?")
            return
        }

        // Nothing to operate on.
        state = .idle
        FloatingOverlay.shared.show(.editToast(
            message: "Select something to edit, or dictate first."
        ))
    }

    private func beginRecording(session: Session, prompt: String) {
        do {
            try recorder.start()
        } catch {
            NSLog("Yap edit-mode record error: \(error)")
            cancel(reason: .error("Couldn't start recording."))
            return
        }
        session.recordingStartedAt = Date()
        state = .recording(session)
        FloatingOverlay.shared.show(.editRecording(
            selection: session.originalText,
            prompt: prompt
        ))
    }

    private func stopAndProcess(session: Session) async {
        let duration = session.recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        session.recordingStartedAt = nil

        let peak = AudioLevels.shared.peakLevel
        guard let url = recorder.stop() else {
            cancel(reason: .userClosed)
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        // Treat too-short or too-quiet recordings as "no instruction given".
        // If a draft exists from a prior attempt (refine flow), drop back to
        // the preview card; otherwise abort the edit session entirely.
        let tooShort = duration < 0.5
        let tooQuiet = peak < 0.15
        guard !tooShort && !tooQuiet else {
            if let draft = session.draft {
                state = .previewing(session)
                FloatingOverlay.shared.show(.editPreview(
                    original: session.originalText,
                    draft: draft,
                    hotkeyLabel: refineHotkeyLabel
                ))
            } else {
                cancel(reason: .userClosed)
            }
            return
        }

        let processingPrompt = session.draft == nil ? "Cooking…" : "Refining…"
        state = .processing(session)
        FloatingOverlay.shared.show(.editProcessing(
            selection: session.originalText,
            prompt: processingPrompt
        ))

        do {
            let (instruction, _) = try await Transcriber.shared.transcribe(wavURL: url)
            let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.lowercased() != "[blank_audio]" else {
                cancel(reason: .userClosed)
                return
            }

            guard let session = currentSessionIfStillProcessing() else { return }

            let appName = appNameForContext(session.source)
            guard let token = Settings.shared.sessionToken, !token.isEmpty else {
                cancel(reason: .error("Not signed in."))
                return
            }

            let spellingVariant = Settings.shared.transcriptionLanguage.spellingVariant
            let preferences = Settings.shared.personalPreferences
            let draft = try await APIClient.shared.edit(
                selection: session.originalText,
                instruction: trimmed,
                appName: appName,
                spellingVariant: spellingVariant,
                preferences: preferences,
                history: session.history,
                session: token
            )

            guard let session = currentSessionIfStillProcessing() else { return }
            let cleaned = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            session.history.append(.init(instruction: trimmed, output: cleaned))
            session.draft = cleaned
            state = .previewing(session)
            FloatingOverlay.shared.show(.editPreview(
                original: session.originalText,
                draft: cleaned,
                hotkeyLabel: refineHotkeyLabel
            ))
        } catch {
            NSLog("Yap edit-mode pipeline error: \(error)")
            cancel(reason: .error("Edit failed: \(error.localizedDescription)"))
        }
    }

    private func appNameForContext(_ source: Source) -> String? {
        switch source {
        case .clipboard(let app): return app?.localizedName
        case .library: return nil
        }
    }

    /// Returns the session iff we're still in `.processing` (i.e. nothing
    /// cancelled us between awaits). Otherwise returns nil — caller should
    /// abort silently.
    private func currentSessionIfStillProcessing() -> Session? {
        if case .processing(let s) = state { return s }
        return nil
    }
}
