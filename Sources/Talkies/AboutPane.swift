import SwiftUI

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 20)

            IconTile(
                systemName: "waveform",
                gradient: LinearGradient(colors: [.mint, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                size: 88,
                cornerRadius: 22,
                iconScale: 0.55
            )

            Text("Talkies")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("Version \(version) · Build \(build)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Dictation that lives on your Mac.\nPush to talk, release to paste.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
