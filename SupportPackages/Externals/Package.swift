// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Externals",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Externals",
            targets: ["Externals", "cpp_test"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Externals",
            dependencies: []),
        .target(
            name: "cpp_test",
            path: "Sources/cpp/cpp_test",
            cSettings: [
                // just test!
                .define("DKGL_CPP_TEST", to:"1234"),

                .define("DKGL_DEBUG_ENABLED", to:"1", .when(configuration: .debug)),
                .define("DKGL_DEBUG_ENABLED", to:"0", .when(configuration: .release)),

                // Graphics API selection
                .define("ENABLE_VULKAN", .when(platforms: [.windows, .linux, .android])),
                .define("ENABLE_METAL", .when(platforms: [.macOS, .iOS])),
                .define("ENABLE_D3D", .when(platforms: [.windows])),

                // GUI Platform
                .define("ENABLE_UIKIT", .when(platforms: [.iOS, .macOS])),
                .define("ENABLE_APPKIT", .when(platforms: [.macOS])),
                .define("ENABLE_WIN32", .when(platforms: [.windows])),
                .define("ENABLE_WAYLAND", .when(platforms: [.linux])),

            ],
            cxxSettings: [
                .define("DKGL_CPP_TEST2", to:"1234"),
                .headerSearchPath("include")
            ]),
    ]
)