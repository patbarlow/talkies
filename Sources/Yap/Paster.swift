import AppKit
import Carbon.HIToolbox

enum Paster {
    @MainActor
    static func paste(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)

        // Give the paste a moment, then restore the original clipboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !saved.isEmpty else { return }
            pasteboard.clearContents()
            for dict in saved {
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                pasteboard.writeObjects([item])
            }
        }
    }
}
