// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TinyGLTF",
    platforms: [.macOS(.v15), .iOS(.v18), .macCatalyst(.v18)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "TinyGLTF",
            targets: ["TinyGLTF"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "TinyGLTF",
            path: "tinygltf",
            sources: ["tiny_gltf_v3.c"],
            publicHeadersPath: ".",
            cSettings: [
                .define("TINYGLTF3_ENABLE_FS"),
                .define("_CRT_SECURE_NO_WARNINGS", .when(platforms: [.windows])),
            ]
        ),
    ],
    cLanguageStandard: .c11
)
