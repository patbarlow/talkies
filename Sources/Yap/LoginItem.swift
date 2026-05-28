import AppKit
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the rest of the app can read/write the
/// "Open at Login" preference without thinking about the underlying API.
///
/// First-launch behaviour: we auto-register on first run so menu-bar apps
/// feel like the kind of utility you set up once and forget. The user can
/// turn it off in Settings.
@MainActor
enum LoginItem {
    private static let firstRunFlagKey = "loginItemRegisteredOnFirstRun"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Called once per launch. On first ever launch we register the app as a
    /// login item; on subsequent launches we leave the user's choice alone.
    static func registerOnFirstRunIfNeeded() {
        // Debug builds aren't packaged as a proper .app bundle, so SMAppService
        // can't register them. Skip silently rather than logging an error every
        // launch.
        guard isInsideAppBundle else { return }
        guard !UserDefaults.standard.bool(forKey: firstRunFlagKey) else { return }
        UserDefaults.standard.set(true, forKey: firstRunFlagKey)
        setEnabled(true)
    }

    /// Returns true if the change was applied. Failures (e.g. user has
    /// disabled the app in System Settings → General → Login Items) are
    /// swallowed — the caller refreshes from `isEnabled` and sees the
    /// authoritative state.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isInsideAppBundle else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Yap: LoginItem.setEnabled(\(enabled)) failed: \(error)")
            return false
        }
    }

    /// Whether `setEnabled` will actually do anything. Returns false for debug
    /// builds (the binary isn't inside a `.app` bundle, so `SMAppService` has
    /// nothing to register). UI surfaces this to disable the toggle rather
    /// than silently no-op'ing.
    static var isAvailable: Bool { isInsideAppBundle }

    private static var isInsideAppBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }
}
