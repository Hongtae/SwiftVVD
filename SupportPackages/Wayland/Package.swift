// swift-tools-version: 5.6
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
            sources: ["Sources"],
            publicHeadersPath: "Sources"
        )
    ],
    cLanguageStandard: .c11
)
