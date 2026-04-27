import SwiftUI

struct KeyboardSetupView: View {
    var body: some View {
        List {
            Section {
                Text("Yap includes a custom keyboard that lets you dictate in any app — messages, notes, emails, anywhere a text field appears.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section("Add the keyboard") {
                step(
                    number: "1",
                    title: "Open Settings",
                    detail: "Go to Settings → General → Keyboard → Keyboards",
                    symbol: "gear"
                )
                step(
                    number: "2",
                    title: "Add New Keyboard",
                    detail: "Tap \"Add New Keyboard…\" and select Yap from the list",
                    symbol: "plus.circle"
                )
                step(
                    number: "3",
                    title: "Allow Full Access",
                    detail: "Tap Yap in the keyboard list, then enable \"Allow Full Access\". This is required for microphone access and network calls.",
                    symbol: "checkmark.shield"
                )
            }

            Section("Using the keyboard") {
                howToRow(
                    symbol: "globe",
                    title: "Switch to Yap",
                    detail: "Tap the globe icon on any keyboard to cycle to Yap"
                )
                howToRow(
                    symbol: "mic.fill",
                    title: "Dictate",
                    detail: "Hold the microphone button and speak. Release to transcribe and insert."
                )
                howToRow(
                    symbol: "gear",
                    title: "Settings",
                    detail: "Tap the gear icon on the Yap keyboard to open this app"
                )
            }

            Section {
                Button(action: openSettings) {
                    Label("Open Settings", systemImage: "gear")
                }
                .tint(.mint)
            }
        }
        .navigationTitle("Keyboard Setup")
        .navigationBarTitleDisplayMode(.large)
    }

    private func step(number: String, title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.mint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(number)
                    .font(.callout.bold())
                    .foregroundStyle(.mint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func howToRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(.mint)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
