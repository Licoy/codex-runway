// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexRunway",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "CodexRunway", targets: ["CodexRunway"]),
        .library(name: "CodexRunwayCore", targets: ["CodexRunwayCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3"),
    ],
    targets: [
        .target(name: "CodexRunwayCore"),
        .executableTarget(
            name: "CodexRunway",
            dependencies: [
                "CodexRunwayCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]),
        .testTarget(
            name: "CodexRunwayCoreTests",
            dependencies: ["CodexRunwayCore"]),
    ])
