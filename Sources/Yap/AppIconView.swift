import AppKit
import SwiftUI

struct AppIconView: View {
    let bundleID: String?
    let size: CGFloat

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: size, height: size)
            }
        }
        .task(id: bundleID) {
            guard let bundleID else { icon = nil; return }
            icon = await resolveIcon(bundleID: bundleID)
        }
    }

    private func resolveIcon(bundleID: String) async -> NSImage? {
        await Task.detached {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }.value
    }
}
