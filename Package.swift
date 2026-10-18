// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanerApp",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CleanerCore"),
        .target(name: "DiskScanner", dependencies: ["CleanerCore"]),
        .testTarget(name: "DiskScannerTests", dependencies: ["DiskScanner", "TestSupport"]),
        .target(name: "Safety", dependencies: ["CleanerCore"]),
        .testTarget(name: "SafetyTests", dependencies: ["Safety", "TestSupport"]),
        .target(name: "Rules", dependencies: ["CleanerCore", "DiskScanner", "Safety"]),
        .testTarget(name: "RulesTests", dependencies: ["Rules", "TestSupport"]),
        .target(name: "Preferences", dependencies: ["CleanerCore"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences", "TestSupport"]),
        .target(name: "TestSupport"),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore", "TestSupport"]),
    ]
)
