import AppKit
import AVFoundation
import Carbon.HIToolbox
import Sparkle
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

    // Sparkle — auto-update controller. `startingUpdater: true` runs periodic
    // background checks per SUScheduledCheckInterval in Info.plist.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    // Menu items that need live updates
    private var weekWordsItem: NSMenuItem!
    private var totalWordsItem: NSMenuItem!
    private var wpmItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildAppMenu()
        buildMenuBar()
        refreshStatus()

        // Hotkey spec rebinding
        NotificationCenter.default.addObserver(
            forName: .yapHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let spec = note.object as? HotkeySpec else { return }
            MainActor.assumeIsolated {
                self?.hotkey?.update(spec: spec)
                self?.refreshStatus()
            }
        }

        // Auth or Accessibility state changed → re-evaluate what to do.
        NotificationCenter.default.addObserver(
            forName: .yapAuthStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        NotificationCenter.default.addObserver(
            forName: .yapAccessibilityChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }

        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        // Settle a moment so the menu-bar icon draws first, then reconcile.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.reconcile()
        }
    }

    /// Decide what to do based on current auth + permissions state.
    /// - Not authenticated: don't touch the hotkey, don't trigger any OS
    ///   prompts; open Settings so the user sees the sign-in pane.
    /// - Authenticated + Accessibility granted: install the hotkey.
    /// - Authenticated + Accessibility missing: open Settings and navigate
    ///   to Permissions so the user can explicitly click Allow.
    private func reconcile() {
        let isAuthed = AuthStore.shared.isSignedIn

        guard isAuthed else {
            hotkey?.uninstall()
            hotkey = nil
            retryTimer?.invalidate()
            retryTimer = nil
            if !(settingsWindow?.isVisible ?? false) { openSettings() }
            refreshStatus()
            return
        }

        if AXIsProcessTrusted() {
            if hotkey == nil { installHotkey() }
        } else {
            SettingsRouter.shared.selection = .permissions
            if !(settingsWindow?.isVisible ?? false) { openSettings() }
        }
        refreshStatus()
    }

    // MARK: - App menu (top-of-screen menu bar when .regular)

    private func buildAppMenu() -> NSMenu {
        let main = NSMenu()

        // App menu — macOS draws the app name as the title of the first submenu.
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "Yap")
        appItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(
            title: "About Yap",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        let checkForUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdates.target = updaterController
        appMenu.addItem(checkForUpdates)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Hide Yap",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit Yap",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // Edit — the standard selectors so Cut/Copy/Paste work in text fields.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a"))

        // Window — minimize / zoom / close for Settings.
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        NSApp.windowsMenu = windowMenu

        return main
    }

    // MARK: - Status-bar menu

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIdleIcon()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        weekWordsItem = NSMenuItem(title: "Words this week: —", action: nil, keyEquivalent: "")
        weekWordsItem.isEnabled = false
        menu.addItem(weekWordsItem)

        totalWordsItem = NSMenuItem(title: "Total words: —", action: nil, keyEquivalent: "")
        totalWordsItem.isEnabled = false
        menu.addItem(totalWordsItem)

        wpmItem = NSMenuItem(title: "Average speed: —", action: nil, keyEquivalent: "")
        wpmItem.isEnabled = false
        menu.addItem(wpmItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Yap", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func setIdleIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Yap")
    }

    private func setRecordingIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
    }

    private func refreshStatus() {
        let stats = Stats.shared
        weekWordsItem.title = "Words this week: \(stats.weekWords.formatted())"
        totalWordsItem.title = "Total words: \(stats.totalWords.formatted())"
        let wpm = stats.averageWPM
        wpmItem.title = wpm > 0
            ? "Average speed: \(Int(wpm)) WPM"
            : "Average speed: —"

        // Reflect tap health in the status-bar icon silently.
        let tapInstalled = hotkey?.isInstalled ?? false
        if tapInstalled {
            if statusItem.button?.image?.accessibilityDescription != "Recording" {
                setIdleIcon()
            }
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: "Not ready")
        }
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
            NSLog("Yap: hotkey pressed")
            self?.startRecording()
        }
        hk.onRelease = { [weak self] in
            NSLog("Yap: hotkey released")
            Task { await self?.stopAndProcess() }
        }
        hk.onCancel = { [weak self] in
            NSLog("Yap: hotkey cancelled (other key pressed)")
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
                    NSLog("Yap: event tap installed after retry")
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
            NSLog("Yap record error: \(error)")
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
            let final: String = Settings.shared.cleanupEnabled
                ? ((try? await Cleaner.shared.clean(raw)) ?? raw)
                : raw
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
            NSLog("Yap pipeline error: \(error)")
        }
        FloatingOverlay.shared.show(.hidden)
    }

    // MARK: - Settings window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let vc = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: vc)
            window.title = "Yap"
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
