// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Wayland",
    products: [
        .library(name: "Wayland", targets: ["Wayland"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "Wayland",
            path: ".",
            exclude: ["Sources/xdg-shell-protocol.c"],
            sources: ["Sources"],
            publicHeadersPath: "Sources",
            cSettings: [
                .define("ENABLE_WAYLAND", .when(platforms: [.linux]))
            ]
        )
    ],
    cLanguageStandard: .c11
)
