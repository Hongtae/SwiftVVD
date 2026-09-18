// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "VGame",
    platforms: [.macOS(.v27), .iOS(.v27), .macCatalyst(.v27)],
    products: [
        .library(name: "VGame", type: .dynamic, targets: ["VGame"]),
    ],
    dependencies: [
        .package(name: "VVD", path: "../VVD"),
    ],
    targets: [
        .target(
            name: "VGame",
            dependencies: [
                .product(name: "VVD", package: "VVD"),
            ],
            path: "Sources",
            packageAccess: false,
            swiftSettings: [
                // Preserve package access across the repository's shared-library packages.
                .unsafeFlags(["-package-name", "swiftvvd"]),
            ]
        ),
    ]
)
