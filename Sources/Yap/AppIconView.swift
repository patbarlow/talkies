import AppKit
import SwiftUI

struct AppIconView: View {
    let bundleID: String?
    let size: CGFloat
    var appName: String? = nil

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
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initial)
                            .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    )
            }
        }
        .task(id: bundleID) {
            guard let bundleID else { icon = nil; return }
            icon = await IconCache.shared.icon(for: bundleID)
        }
    }

    private var initial: String {
        appName.flatMap { $0.first.map(String.init) }?.uppercased() ?? ""
    }
}

@MainActor
private final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for bundleID: String) async -> NSImage? {
        if let cached = cache[bundleID] { return cached }

        // 1. Local install — instant, no network
        if let img = await Task.detached(priority: .userInitiated, operation: {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil as NSImage? }
            return NSWorkspace.shared.icon(forFile: url.path)
        }).value {
            cache[bundleID] = img
            return img
        }

        // 2. iTunes API — covers any App Store app regardless of local install
        if let img = await fetchFromItunes(bundleID: bundleID) {
            cache[bundleID] = img
            return img
        }

        return nil
    }

    private func fetchFromItunes(bundleID: String) async -> NSImage? {
        guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url else { return nil }

        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }

        struct Response: Decodable {
            struct Result: Decodable { let artworkUrl512: String? }
            let results: [Result]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let artworkURLString = decoded.results.first?.artworkUrl512,
              let artworkURL = URL(string: artworkURLString),
              let (imgData, _) = try? await URLSession.shared.data(from: artworkURL),
              let img = NSImage(data: imgData)
        else { return nil }

        return img
    }
}
