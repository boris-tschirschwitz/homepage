// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "homepage",
    platforms: [
        .macOS(.v10_14),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "homepage",
            dependencies: ["NIO", "NIOHTTP1", "Logging", "SPMUtility"]),
        .testTarget(
            name: "homepageTests",
            dependencies: ["homepage"]),
    ]
)
