import SwiftUI
import AVFoundation

@main
struct YapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthStore.shared
    @StateObject private var settings = SharedSettings.shared
    @StateObject private var library = Library.shared
    @StateObject private var warmupRecorder = Recorder()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(settings)
                .environmentObject(library)
                .task {
                    // Sync pending library entries from keyboard extension sessions
                    await SessionSyncer.shared.syncPending()
                    // Reload in case keyboard extension added entries while app was closed
                    Library.shared.reload()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        SharedDefaults.set(Date(), for: .appBecameActiveAt)
                    }
                }
                .onOpenURL { url in
                    guard url.host == "keyboard-warmup" else { return }
                    Task { @MainActor in
                        await runKeyboardMicWarmup()
                    }
                }
        }
    }

    @MainActor
    private func runKeyboardMicWarmup() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            primeRecorder()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted { primeRecorder() }
        default:
            break
        }
    }

    @MainActor
    private func primeRecorder() {
        do {
            try warmupRecorder.start()
            if let url = warmupRecorder.stop() {
                try? FileManager.default.removeItem(at: url)
            }
            SharedDefaults.set(Date(), for: .appBecameActiveAt)
        } catch {
            _ = warmupRecorder.stop()
        }
    }
}
