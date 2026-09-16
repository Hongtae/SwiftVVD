// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "miniaudio",
    products: [
        .library(
            name: "miniaudio",
            type: .static,
            targets: ["miniaudio"]),
    ],
    targets: [
        .target(
            name: "miniaudio",
            path: "miniaudio",
            sources: [
                "miniaudio.c",
                "miniaudio.m",
            ],
            publicHeadersPath: ".",
            cSettings: [
                .define("_CRT_SECURE_NO_WARNINGS", .when(platforms: [.windows])),
            ]),
    ],
    cLanguageStandard: .c11
)
