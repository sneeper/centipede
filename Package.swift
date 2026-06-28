// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Centipede",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Centipede",
            path: "Sources/Centipede"
        )
    ]
)
