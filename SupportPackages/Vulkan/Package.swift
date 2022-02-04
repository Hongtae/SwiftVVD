// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Vulkan",
    products: [
        .library(name: "Vulkan", targets: ["Vulkan"]),
    ],
    dependencies: [],
    targets: [
        .systemLibrary(name: "Vulkan"),
    ],
    cLanguageStandard: .c11
)