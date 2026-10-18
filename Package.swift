// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanerApp",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CleanerCore"),
        .target(name: "DiskScanner", dependencies: ["CleanerCore"]),
        .testTarget(name: "DiskScannerTests", dependencies: ["DiskScanner", "TestSupport"]),
        .target(name: "TestSupport"),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore", "TestSupport"]),
    ]
)
