import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        if auth.isSignedIn {
            MainTabView()
        } else {
            SignInView()
        }
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "mic.circle.fill") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(.mint)
    }
}
