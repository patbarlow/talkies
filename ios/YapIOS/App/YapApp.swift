import SwiftUI

@main
struct YapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthStore.shared
    @StateObject private var settings = SharedSettings.shared
    @StateObject private var library = Library.shared

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
        }
    }
}
