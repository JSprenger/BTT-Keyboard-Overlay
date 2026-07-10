// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyboardOverlay",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KeyboardOverlay",
            path: "Sources/KeyboardOverlay",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
