// swift-tools-version:5.9
import PackageDescription

// MacPortsUI — a native SwiftUI reference UI for managing MacPorts.
//
// Build/run (no Xcode required, works with Command Line Tools):
//   swift build
//   swift run MacPortsUI
//
// Architecture:
//   - MacPortsUICore (library): models, parsers, the port CLI runner, and the
//     service facade. Pure Foundation/Combine, no SwiftUI, fully unit-testable.
//   - MacPortsUI (executable): the SwiftUI shell (views + @main app).
let package = Package(
    name: "MacPortsUI",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .target(
            name: "MacPortsUICore",
            path: "Sources/MacPortsUICore",
            linkerSettings: [
                // Kept for a future SQLite registry.db reader; the MVP reads
                // state by shelling out to `port`, so this is a no-op today.
                .linkedLibrary("sqlite3"),
            ]
        ),

        .executableTarget(
            name: "MacPortsUI",
            dependencies: ["MacPortsUICore"],
            path: "Sources/MacPortsUI"
        ),

        .testTarget(
            name: "MacPortsUITests",
            dependencies: ["MacPortsUICore"],
            path: "Tests/MacPortsUITests"
        ),
    ]
)
