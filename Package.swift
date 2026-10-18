// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanerApp",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "CleanerApp", targets: ["CleanerApp"])],
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
        .target(name: "AI", dependencies: ["CleanerCore", "Preferences"]),
        .testTarget(name: "AITests", dependencies: ["AI", "Preferences", "TestSupport"]),
        .target(name: "Cleaning", dependencies: ["CleanerCore", "Safety"]),
        .testTarget(name: "CleaningTests", dependencies: ["Cleaning", "TestSupport"]),
        .target(name: "AppModel", dependencies: ["CleanerCore", "Rules", "Safety", "Preferences", "AI", "Cleaning"]),
        .testTarget(name: "AppModelTests", dependencies: ["AppModel", "Rules", "TestSupport"]),
        .executableTarget(name: "CleanerApp",
                          dependencies: ["AppModel", "CleanerCore", "AI", "Cleaning", "Preferences"]),
        .target(name: "TestSupport", dependencies: ["AI", "Cleaning"]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore", "TestSupport"]),
    ]
)
