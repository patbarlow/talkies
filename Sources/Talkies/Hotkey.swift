import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// A push-to-talk binding. Either a regular key (F5, letters, …) or a single modifier (right-⌘, fn, …).
struct HotkeySpec: Codable, Equatable {
    enum Kind: String, Codable { case key, modifier }

    var kind: Kind
    var keyCode: UInt16
    var label: String

    static let defaultSpec = HotkeySpec(
        kind: .modifier,
        keyCode: UInt16(kVK_RightCommand),
        label: "Right ⌘"
    )

    /// Device-specific flag bit for a modifier key. Zero for non-modifier codes.
    /// These constants come from IOKit/hidsystem/ev_keymap.h and are included in CGEventFlags.rawValue.
    static func deviceFlag(for keyCode: UInt16) -> UInt64 {
        switch Int(keyCode) {
        case kVK_Control:       return 0x00000001
        case kVK_Shift:         return 0x00000002
        case kVK_RightShift:    return 0x00000004
        case kVK_Command:       return 0x00000008
        case kVK_RightCommand:  return 0x00000010
        case kVK_Option:        return 0x00000020
        case kVK_RightOption:   return 0x00000040
        case kVK_RightControl:  return 0x00002000
        case kVK_Function:      return 0x00800000
        default:                return 0
        }
    }

    static func isModifier(_ keyCode: UInt16) -> Bool {
        deviceFlag(for: keyCode) != 0
    }

    static func modifierLabel(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Command:       return "Left ⌘"
        case kVK_RightCommand:  return "Right ⌘"
        case kVK_Option:        return "Left ⌥"
        case kVK_RightOption:   return "Right ⌥"
        case kVK_Shift:         return "Left ⇧"
        case kVK_RightShift:    return "Right ⇧"
        case kVK_Control:       return "Left ⌃"
        case kVK_RightControl:  return "Right ⌃"
        case kVK_Function:      return "fn"
        default:                return "Modifier \(keyCode)"
        }
    }

    static func keyLabel(for keyCode: UInt16, fallbackChars: String? = nil) -> String {
        let map: [Int: String] = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
            kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
            kVK_Space: "Space", kVK_Tab: "Tab", kVK_Return: "Return", kVK_Escape: "Esc",
            kVK_Delete: "Delete", kVK_ForwardDelete: "Fwd Delete",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        if let label = map[Int(keyCode)] { return label }
        if let chars = fallbackChars?.trimmingCharacters(in: .whitespaces), !chars.isEmpty {
            return chars.uppercased()
        }
        return "Key \(keyCode)"
    }
}

/// Installs a `CGEventTap` to drive push-to-talk callbacks.
/// For regular keys: swallows the key so host apps don't react.
/// For modifier-only: passes the event through, and cancels the session if another key is pressed.
final class Hotkey {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var spec: HotkeySpec
    private var isDown = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isInstalled: Bool { eventTap != nil }

    init(spec: HotkeySpec) {
        self.spec = spec
    }

    @discardableResult
    func update(spec: HotkeySpec) -> Bool {
        uninstall()
        self.spec = spec
        return install()
    }

    @discardableResult
    func install() -> Bool {
        if eventTap != nil { return true }

        let mask: CGEventMask
        switch spec.kind {
        case .key:
            mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        case .modifier:
            mask =
                (1 << CGEventType.flagsChanged.rawValue) |
                (1 << CGEventType.keyDown.rawValue)
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<Hotkey>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                NSLog("Talkies: event tap re-enabled after being disabled by system")
                return Unmanaged.passUnretained(event)
            }

            return me.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Talkies: CGEvent.tapCreate returned nil — Accessibility permission likely not granted yet.")
            return false
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Talkies: event tap installed for \(spec.label) (kind=\(spec.kind.rawValue), keyCode=\(spec.keyCode))")
        return true
    }

    func uninstall() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        isDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch spec.kind {
        case .key:
            guard code == spec.keyCode else { return Unmanaged.passUnretained(event) }
            if type == .keyDown {
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                if !isDown {
                    isDown = true
                    DispatchQueue.main.async { self.onPress?() }
                }
                return nil
            }
            if type == .keyUp, isDown {
                isDown = false
                DispatchQueue.main.async { self.onRelease?() }
                return nil
            }
            return nil

        case .modifier:
            if type == .flagsChanged, code == spec.keyCode {
                let bit = HotkeySpec.deviceFlag(for: spec.keyCode)
                let isPressed = (event.flags.rawValue & bit) != 0
                if isPressed, !isDown {
                    isDown = true
                    DispatchQueue.main.async { self.onPress?() }
                } else if !isPressed, isDown {
                    isDown = false
                    DispatchQueue.main.async { self.onRelease?() }
                }
                return Unmanaged.passUnretained(event)
            }
            // Another key pressed while the modifier is held → cancel the session
            // so real shortcuts like right-⌘+C still work.
            if type == .keyDown, isDown {
                isDown = false
                DispatchQueue.main.async { self.onCancel?() }
                return Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }
    }
}
