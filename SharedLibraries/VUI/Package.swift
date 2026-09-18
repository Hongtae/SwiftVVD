// swift-tools-version: 6.4

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "VUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v27), .iOS(.v27), .macCatalyst(.v27)],
    products: [
        .library(name: "VUI", type: .dynamic, targets: ["VUI"]),
    ],
    dependencies: [
        .package(name: "VVD", path: "../VVD"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.2"),
    ],
    targets: [
        .target(
            name: "VUI",
            dependencies: [
                .product(name: "VVD", package: "VVD"),
                .target(name: "VUIMacros"),
            ],
            exclude: [
                "Resources/Shaders/HLSL",
                "Resources/Shaders/gen_hlsl_spv.py",
            ],
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/Shaders/SPIRV"),
                .copy("Resources/Symbols"),
                .copy("Resources/Presets"),
            ],
            packageAccess: false,
            swiftSettings: [
                // Preserve package access across the repository's shared-library packages.
                .unsafeFlags(["-package-name", "swiftvvd"]),
            ]
        ),
        .macro(
            name: "VUIMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
    ]
)
