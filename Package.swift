// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DKGame",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "DKGame",
            type: .dynamic,
            targets: ["DKGame"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "cpp_test",
            path: "Sources/DKGame/cpp/cpp_test",
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
        .target(
            name: "DKGame",
            dependencies: ["cpp_test"],
            exclude: [
                "cpp"
            ],
            linkerSettings: [
                .linkedLibrary("User32"),
                .linkedLibrary("Ole32"),
                .linkedLibrary("Imm32"),
                .linkedLibrary("Shcore")
            ]),
        .testTarget(
            name: "DKGameTests",
            dependencies: ["DKGame"]),
        .executableTarget(
            name: "TestApp1",
            dependencies: ["DKGame"],
            linkerSettings: []),
    ]
)
