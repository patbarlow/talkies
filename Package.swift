// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Talkies",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Talkies",
            path: "Sources/Talkies"
        )
    ]
)
