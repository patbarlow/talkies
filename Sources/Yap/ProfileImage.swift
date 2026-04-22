import AppKit
import Foundation
import SwiftUI

@MainActor
final class ProfileImage: ObservableObject {
    static let shared = ProfileImage()

    @Published private(set) var image: NSImage?
    @Published private(set) var isSyncing = false

    private let url: URL

    private init() {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("Yap", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("avatar.png")
        load()
    }

    private func load() {
        image = NSImage(contentsOf: url)
    }

    func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image for your Yap profile"
        panel.begin { [weak self] result in
            guard result == .OK, let picked = panel.url else { return }
            Task { @MainActor in self?.save(from: picked) }
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
        image = nil
    }

    /// Download the avatar from the backend if we don't have a local copy.
    func syncFromServer(session: String) {
        guard image == nil else { return }
        Task {
            do {
                let png = try await APIClient.shared.downloadAvatar(session: session)
                try png.write(to: url, options: .atomic)
                load()
            } catch {
                NSLog("Yap: avatar download skipped: \(error)")
            }
        }
    }

    /// Scale to 256×256, save locally, and upload to backend.
    private func save(from source: URL) {
        guard let loaded = NSImage(contentsOf: source) else { return }
        let size = NSSize(width: 256, height: 256)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        let srcSize = loaded.size
        let scale = max(size.width / srcSize.width, size.height / srcSize.height)
        let scaled = NSSize(width: srcSize.width * scale, height: srcSize.height * scale)
        let origin = NSPoint(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2)
        loaded.draw(
            in: NSRect(origin: origin, size: scaled),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: url, options: .atomic)
            let resized = NSImage(size: size)
            resized.addRepresentation(bitmap)
            image = resized
            uploadToServer(pngData: png)
        } catch {
            NSLog("Yap: failed to save avatar: \(error)")
        }
    }

    private func uploadToServer(pngData: Data) {
        guard let session = Settings.shared.sessionToken else { return }
        isSyncing = true
        Task {
            defer { isSyncing = false }
            do {
                try await APIClient.shared.uploadAvatar(pngData: pngData, session: session)
            } catch {
                NSLog("Yap: avatar upload failed: \(error)")
            }
        }
    }
}
