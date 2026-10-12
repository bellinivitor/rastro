// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevTimeline",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DevTimeline", targets: ["DevTimeline"]),
    ],
    targets: [
        // Lógica sem UI (git, parsing, estatísticas, banco SQLite).
        .target(name: "DevTimelineCore"),
        // App SwiftUI. O build do dia a dia é Scripts/build.sh (make run).
        .executableTarget(
            name: "DevTimeline",
            dependencies: ["DevTimelineCore"]
        ),
        .testTarget(
            name: "DevTimelineCoreTests",
            dependencies: ["DevTimelineCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
