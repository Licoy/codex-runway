// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexRunway",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "CodexRunway", targets: ["CodexRunway"]),
        .executable(name: "CodexRunwayCostBenchmark", targets: ["CodexRunwayCostBenchmark"]),
        .library(name: "CodexRunwayCore", targets: ["CodexRunwayCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Mijick/CalendarView.git", exact: "1.1.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3"),
    ],
    targets: [
        .target(
            name: "CodexRunwayCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]),
        .executableTarget(
            name: "CodexRunway",
            dependencies: [
                "CodexRunwayCore",
                .product(name: "MijickCalendarView", package: "CalendarView"),
                .product(name: "Sparkle", package: "Sparkle"),
            ]),
        .executableTarget(
            name: "CodexRunwayCostBenchmark",
            dependencies: ["CodexRunwayCore"]),
        .testTarget(
            name: "CodexRunwayCoreTests",
            dependencies: ["CodexRunwayCore"]),
        .testTarget(
            name: "CodexRunwayTests",
            dependencies: ["CodexRunway", "CodexRunwayCore"]),
    ])
