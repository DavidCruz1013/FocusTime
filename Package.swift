// swift-tools-version: 5.9
import PackageDescription

// Pruebas de persistencia independientes de SwiftUI y Screen Time.
let package = Package(
    name: "FocusTimeData",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "FocusData",
            path: "FocusTime/Data",
            sources: ["Database.swift", "FocusRepository.swift", "Models.swift", "ManualUsageRepository.swift"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "FocusDataTests", dependencies: ["FocusData"])
    ]
)
