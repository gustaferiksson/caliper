// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "caliper",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "caliper", path: "Sources/caliper")
    ]
)
