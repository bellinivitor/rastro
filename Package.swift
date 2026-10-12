// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rastro",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Rastro", targets: ["Rastro"]),
    ],
    targets: [
        // Lógica sem UI (git, parsing, estatísticas, banco SQLite).
        .target(name: "RastroCore"),
        // App SwiftUI. O build do dia a dia é Scripts/build.sh (make run).
        .executableTarget(
            name: "Rastro",
            dependencies: ["RastroCore"]
        ),
        .testTarget(
            name: "RastroCoreTests",
            dependencies: ["RastroCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
