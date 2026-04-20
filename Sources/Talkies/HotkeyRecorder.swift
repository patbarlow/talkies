import AppKit
import SwiftUI

/// Click the button, press your desired key or modifier, done.
/// Uses a local NSEvent monitor so it only intercepts events while the Settings window is frontmost.
struct HotkeyRecorder: View {
    @Binding var spec: HotkeySpec
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(action: toggle) {
                Text(isRecording ? "Press any key or modifier… (Esc to cancel)" : spec.label)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        }
        .onDisappear { stop() }
    }

    private func toggle() {
        if isRecording { stop() } else { start() }
    }

    private func start() {
        stop()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let code = UInt16(event.keyCode)

            if event.type == .keyDown {
                // Escape cancels the recording.
                if Int(code) == 0x35 { // kVK_Escape
                    stop()
                    return nil
                }
                let label = HotkeySpec.keyLabel(for: code, fallbackChars: event.charactersIgnoringModifiers)
                commit(HotkeySpec(kind: .key, keyCode: code, label: label))
                return nil
            }

            if event.type == .flagsChanged, HotkeySpec.isModifier(code) {
                // Only capture on the *press* edge (the device bit just turned on).
                let bit = HotkeySpec.deviceFlag(for: code)
                if (event.modifierFlags.rawValue & UInt(bit)) != 0 {
                    commit(HotkeySpec(kind: .modifier, keyCode: code, label: HotkeySpec.modifierLabel(for: code)))
                }
                return nil
            }

            return event
        }
    }

    private func commit(_ newSpec: HotkeySpec) {
        spec = newSpec
        stop()
    }

    private func stop() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
