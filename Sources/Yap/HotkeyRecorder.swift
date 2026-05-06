import AppKit
import Carbon.HIToolbox
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

/// Pop-up–menu picker for an optional `HotkeySpec`. Shows preset options,
/// a "Custom…" entry that drops into a recorder, and a "No shortcut" entry
/// that clears the binding. Used by both the dictation and edit hotkeys.
struct HotkeyPicker: View {
    @Binding var spec: HotkeySpec?
    var presets: [HotkeySpec] = HotkeyPicker.defaultPresets
    var disabled: Bool = false

    /// Default preset list. Modifier-only bindings (single keys held down)
    /// since Yap is push-to-hold and doesn't support modifier+key combos.
    static let defaultPresets: [HotkeySpec] = [
        HotkeySpec(kind: .modifier, keyCode: UInt16(kVK_RightCommand), label: "Right ⌘"),
        HotkeySpec(kind: .modifier, keyCode: UInt16(kVK_RightOption),  label: "Right ⌥"),
        HotkeySpec(kind: .modifier, keyCode: UInt16(kVK_Function),     label: "fn"),
    ]

    @State private var awaitingCustom = false
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            menu
            if awaitingCustom {
                Button(action: toggleRecording) {
                    Text(isRecording ? "Press any key or modifier… (Esc to cancel)" : "Set shortcut")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .disabled(disabled)
            }
        }
        .onDisappear { stopRecording() }
        .onChange(of: disabled) { _, newValue in
            if newValue {
                stopRecording()
                awaitingCustom = false
            }
        }
    }

    private var menu: some View {
        Menu {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                Button {
                    selectPreset(preset)
                } label: {
                    HStack {
                        Text(preset.label)
                        if isCurrent(preset) { Image(systemName: "checkmark") }
                    }
                }
            }
            Button {
                selectCustom()
            } label: {
                HStack {
                    Text("Custom…")
                    if showsCustomCheckmark { Image(systemName: "checkmark") }
                }
            }
            Divider()
            Button {
                selectNone()
            } label: {
                HStack {
                    Text("No shortcut")
                    if spec == nil && !awaitingCustom { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text(currentLabel)
                    .foregroundStyle(disabled ? .secondary : .primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(disabled)
    }

    // MARK: Display

    private var currentLabel: String {
        if awaitingCustom && spec == nil { return "Custom…" }
        guard let spec else { return "No shortcut" }
        return spec.label
    }

    private var showsCustomCheckmark: Bool {
        if awaitingCustom { return true }
        guard let spec else { return false }
        return !presets.contains { isMatch($0, spec) }
    }

    private func isCurrent(_ preset: HotkeySpec) -> Bool {
        guard !awaitingCustom, let spec else { return false }
        return isMatch(preset, spec)
    }

    private func isMatch(_ a: HotkeySpec, _ b: HotkeySpec) -> Bool {
        a.kind == b.kind && a.keyCode == b.keyCode
    }

    // MARK: Selection actions

    private func selectPreset(_ preset: HotkeySpec) {
        stopRecording()
        awaitingCustom = false
        spec = preset
    }

    private func selectCustom() {
        awaitingCustom = true
    }

    private func selectNone() {
        stopRecording()
        awaitingCustom = false
        spec = nil
    }

    // MARK: Recording

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let code = UInt16(event.keyCode)

            if event.type == .keyDown {
                if Int(code) == 0x35 { // kVK_Escape
                    stopRecording()
                    return nil
                }
                let label = HotkeySpec.keyLabel(for: code, fallbackChars: event.charactersIgnoringModifiers)
                commit(HotkeySpec(kind: .key, keyCode: code, label: label))
                return nil
            }

            if event.type == .flagsChanged, HotkeySpec.isModifier(code) {
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
        awaitingCustom = false
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
