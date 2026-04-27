import UIKit
import SwiftUI

@MainActor
final class ProfileImage: ObservableObject {
    static let shared = ProfileImage()

    @Published private(set) var image: UIImage?
    @Published private(set) var isSyncing = false

    private let url: URL

    private init() {
        let fm = FileManager.default
        let base: URL
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.app.yap") {
            base = groupURL
        } else {
            base = (try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fm.temporaryDirectory
        }
        let dir = base.appendingPathComponent("Profile", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("avatar.png")
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: url) {
            image = UIImage(data: data)
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
        image = nil
    }

    func syncFromServer(session: String) {
        guard image == nil else { return }
        Task {
            do {
                let png = try await APIClient.shared.downloadAvatar(session: session)
                try png.write(to: url, options: .atomic)
                load()
            } catch {}
        }
    }

    /// Scale to 256×256, save locally, and upload to backend.
    func save(image sourceImage: UIImage) {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { ctx in
            let srcSize = sourceImage.size
            let scale = max(size.width / srcSize.width, size.height / srcSize.height)
            let scaled = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
            let origin = CGPoint(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2)
            sourceImage.draw(in: CGRect(origin: origin, size: scaled))
        }
        guard let png = resized.pngData() else { return }
        do {
            try png.write(to: url, options: .atomic)
            image = resized
            uploadToServer(pngData: png)
        } catch {}
    }

    private func uploadToServer(pngData: Data) {
        guard let session = SharedSettings.shared.sessionToken else { return }
        isSyncing = true
        Task {
            defer { isSyncing = false }
            try? await APIClient.shared.uploadAvatar(pngData: pngData, session: session)
        }
    }
}
