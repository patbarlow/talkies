import AppKit
import Carbon.HIToolbox

/// Synthesizes ⌘C to capture whatever the user has selected in the frontmost
/// app, then restores the original pasteboard. Used when AX selection-read
/// fails (Electron apps and similar) or for the explicit "edit clipboard"
/// hotkey.
///
/// The pasteboard is restored before this returns, so callers can
/// optionally do their own clipboard manipulation afterwards (e.g. paste an
/// edited result back) without conflicting.
enum ClipboardProbe {
    struct Snapshot {
        /// Text we observed on the pasteboard after the synthesized ⌘C.
        /// nil if `changeCount` didn't move (i.e. nothing was selected).
        let copiedText: String?
        /// The frontmost app at probe time. Captured so the caller can
        /// reactivate it before pasting back.
        let app: NSRunningApplication?
    }

    @MainActor
    static func probe() async -> Snapshot {
        let pasteboard = NSPasteboard.general
        let app = NSWorkspace.shared.frontmostApplication

        // Snapshot existing pasteboard contents AND the changeCount. We
        // restore contents at the end and use the changeCount to detect
        // whether the synthesized ⌘C actually copied anything.
        let originalChangeCount = pasteboard.changeCount
        let saved: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        } ?? []

        synthesizeCopy()

        // Wait for the OS to actually update the pasteboard. This isn't
        // instant — typical latency is 30-80ms in cooperating apps, longer
        // in Electron. 150ms is a comfortable upper bound.
        try? await Task.sleep(nanoseconds: 150_000_000)

        var copied: String? = nil
        if pasteboard.changeCount != originalChangeCount {
            copied = pasteboard.string(forType: .string)
        }

        // Restore.
        pasteboard.clearContents()
        if !saved.isEmpty {
            for dict in saved {
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                pasteboard.writeObjects([item])
            }
        }

        let trimmed = copied?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Snapshot(
            copiedText: (trimmed?.isEmpty == false) ? copied : nil,
            app: app
        )
    }

    private static func synthesizeCopy() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cCode = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: src, virtualKey: cCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: cCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
