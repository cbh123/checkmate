// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Checkmate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Checkmate", path: "Sources/Checkmate"),
    ]
)
