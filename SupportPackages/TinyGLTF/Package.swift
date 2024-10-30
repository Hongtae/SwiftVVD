// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TinyGLTF",
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
            sources: ["tiny_gltf.cc"],
            publicHeadersPath: ".",
            cxxSettings: [
                .define("__STDC_LIB_EXT1__", .when(platforms: [.windows])),
                .define("NOMINMAX", .when(platforms: [.windows])),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx14
)
