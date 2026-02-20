// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MufusMac",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MufusMac",
            path: "Sources/MufusMac"
        )
    ]
)
