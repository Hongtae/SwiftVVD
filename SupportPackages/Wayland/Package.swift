// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Wayland",
    products: [
        .library(name: "Wayland", type: .static, targets: ["Wayland"]),
    ],
    targets: [
        .target(name: "Wayland",
            path: "Sources",
            exclude: ["protocols"],
            sources: ["wayland.c"],
            publicHeadersPath: ".",
            cSettings: [
                .define("ENABLE_WAYLAND", .when(platforms: [.linux]))
            ]
        )
    ],
    cLanguageStandard: .c11
)
