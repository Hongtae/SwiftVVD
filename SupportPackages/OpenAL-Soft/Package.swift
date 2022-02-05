// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OepnAL-Soft",
    products: [
        .library(
            name: "OpenAL",
            type: .dynamic,
            targets: ["OpenAL"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OpenAL",
            path: "Sources",
            sources: [
                "al",
                "alc",
                "common",
                "core",
            ],
            publicHeadersPath: "include"),
    ],
    cLanguageStandard: .c11
)
