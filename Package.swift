// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "eventjarvis",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "eventjarvis",
            path: "Sources/EventJarvis",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
