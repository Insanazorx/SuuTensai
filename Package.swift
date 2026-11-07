// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SuuTensai",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RigorCore", targets: ["SuuTensai"]),
        .executable(name: "SuuTensai", targets: ["SuuTensaiCLI"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SuuTensai",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .executableTarget(
            name: "SuuTensaiCLI",
            dependencies: ["SuuTensai"],
        ),
        .testTarget(
            name: "SuuTensaiTests",
            dependencies: ["SuuTensai"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
