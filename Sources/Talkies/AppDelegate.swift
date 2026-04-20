import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkey: Hotkey?
    private let recorder = Recorder()
    private var isRecording = false
    private var settingsWindow: NSWindow?

    private var retryTimer: Timer?
    private var recordingStartedAt: Date?

    // Menu items that need live updates
    private var hotkeyStatusItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var microphoneItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBar()
        installHotkey()
        refreshStatus()

        NotificationCenter.default.addObserver(
            forName: .talkiesHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let spec = note.object as? HotkeySpec else { return }
            MainActor.assumeIsolated {
                self?.hotkey?.update(spec: spec)
                self?.refreshStatus()
            }
        }

        // First-launch: open Settings → Permissions so the user sees an explicit setup flow
        // instead of silent system prompts.
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        if firstLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                SettingsRouter.shared.selection = .permissions
                self?.openSettings()
            }
        }
    }

    // MARK: - Menu

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIdleIcon()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        hotkeyStatusItem = NSMenuItem(title: "Hotkey: —", action: nil, keyEquivalent: "")
        hotkeyStatusItem.isEnabled = false
        menu.addItem(hotkeyStatusItem)

        accessibilityItem = NSMenuItem(title: "Accessibility: —", action: nil, keyEquivalent: "")
        accessibilityItem.isEnabled = false
        menu.addItem(accessibilityItem)

        microphoneItem = NSMenuItem(title: "Microphone: —", action: nil, keyEquivalent: "")
        microphoneItem.isEnabled = false
        menu.addItem(microphoneItem)

        menu.addItem(.separator())

        let reinstall = NSMenuItem(title: "Reinstall Hotkey", action: #selector(reinstallHotkey), keyEquivalent: "")
        reinstall.target = self
        menu.addItem(reinstall)

        let openAX = NSMenuItem(title: "Open Privacy & Security Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        openAX.target = self
        menu.addItem(openAX)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Talkies", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func setIdleIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Talkies")
    }

    private func setRecordingIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
    }

    private func refreshStatus() {
        let ax = AXIsProcessTrusted()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let tapInstalled = hotkey?.isInstalled ?? false

        hotkeyStatusItem.title = "Hotkey: \(Settings.shared.hotkey.label) \(tapInstalled ? "✓" : "✗")"
        accessibilityItem.title = "Accessibility: \(ax ? "✓" : "✗ — required")"
        microphoneItem.title = "Microphone: \(mic ? "✓" : "✗ — required")"

        if tapInstalled {
            if statusItem.button?.image?.accessibilityDescription != "Recording" {
                setIdleIcon()
            }
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: "Not ready")
        }
    }

    // MARK: - Permissions

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Hotkey

    @objc private func reinstallHotkey() {
        hotkey?.uninstall()
        installHotkey()
        refreshStatus()
    }

    private func installHotkey() {
        let hk = hotkey ?? Hotkey(spec: Settings.shared.hotkey)
        hk.onPress = { [weak self] in
            NSLog("Talkies: hotkey pressed")
            self?.startRecording()
        }
        hk.onRelease = { [weak self] in
            NSLog("Talkies: hotkey released")
            Task { await self?.stopAndProcess() }
        }
        hk.onCancel = { [weak self] in
            NSLog("Talkies: hotkey cancelled (other key pressed)")
            self?.cancelRecording()
        }
        hotkey = hk

        if hk.install() {
            retryTimer?.invalidate()
            retryTimer = nil
        } else {
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let hk = self.hotkey else { t.invalidate(); return }
                guard AXIsProcessTrusted() else { return }
                if hk.install() {
                    NSLog("Talkies: event tap installed after retry")
                    t.invalidate()
                    self.retryTimer = nil
                    self.refreshStatus()
                }
            }
        }
    }

    // MARK: - Recording pipeline

    private func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingStartedAt = nil
        setIdleIcon()
        _ = recorder.stop()
        FloatingOverlay.shared.show(.hidden)
    }

    private func startRecording() {
        guard !isRecording else { return }
        do {
            try recorder.start()
            recordingStartedAt = Date()
            isRecording = true
            setRecordingIcon()
            FloatingOverlay.shared.show(.recording)
        } catch {
            NSLog("Talkies record error: \(error)")
        }
    }

    private func stopAndProcess() async {
        guard isRecording else { return }
        isRecording = false
        setIdleIcon()
        let duration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil

        guard let url = recorder.stop() else {
            FloatingOverlay.shared.show(.hidden)
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        FloatingOverlay.shared.show(.processing)
        do {
            let raw = try await Transcriber.shared.transcribe(wavURL: url)
            let final: String
            if Settings.shared.cleanupEnabled, Settings.shared.anthropicKey?.isEmpty == false {
                final = (try? await Cleaner.shared.clean(raw)) ?? raw
            } else {
                final = raw
            }
            // Capture the target app BEFORE we paste — the synthesized ⌘V may briefly steal focus.
            let target = NSWorkspace.shared.frontmostApplication
            Paster.paste(final)
            Stats.shared.record(text: final, duration: duration)
            Library.shared.record(
                raw: raw,
                final: final,
                duration: duration,
                appName: target?.localizedName,
                bundleID: target?.bundleIdentifier
            )
        } catch {
            NSLog("Talkies pipeline error: \(error)")
        }
        FloatingOverlay.shared.show(.hidden)
    }

    // MARK: - Settings window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let vc = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: vc)
            window.title = "Talkies"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.toolbarStyle = .unifiedCompact
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 860, height: 600))
            window.minSize = NSSize(width: 760, height: 520)
            window.center()
            window.delegate = self
            settingsWindow = window
        }

        // Temporarily promote to a regular app so the user gets proper window
        // chrome, a menu bar (File / Edit / Window), and Cmd-Tab switching
        // while Settings is open. Flips back to accessory on close.
        NSApp.setActivationPolicy(.regular)

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in self.refreshStatus() }
    }
}

extension AppDelegate: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            guard let window = notification.object as? NSWindow,
                  window === self.settingsWindow else { return }
            // Back to menu-bar-only accessory app once Settings closes.
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
