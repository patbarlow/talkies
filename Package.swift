// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Yap",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Yap",
            path: "Sources/Yap"
        )
    ]
)
