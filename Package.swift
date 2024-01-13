// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DKGame",
    platforms: [.macOS(.v14), .iOS(.v17), .macCatalyst(.v17)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(name: "DKGame", type: .dynamic, targets: ["DKGame"]),
        .library(name: "DKGUI", type: .dynamic, targets: ["DKGUI"]),
        .executable(name: "DKGameEditor", targets: ["DKGameEditor"]),
        .executable(name: "TestApp1", targets: ["TestApp1"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(
            name: "DKGame-ThirdParty",
            path: "SupportPackages/DKGame-ThirdParty"),
        .package(
            name: "Vulkan",
            path: "SupportPackages/Vulkan"),
        .package(
            name: "Wayland",
            path: "SupportPackages/Wayland"),
        .package(
            url: "https://github.com/Hongtae/swift-openal-soft.git",
            branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "DKGame",
            dependencies: [
                .product(
                    name: "DKGame-ThirdParty",
                    package: "DKGame-ThirdParty"),
                .product(
                    name: "Vulkan",
                    package: "Vulkan",
                    condition: .when(platforms: [.windows, .linux, .android])),
                .product(
                    name: "Wayland",
                    package: "Wayland",
                    condition: .when(platforms: [.linux])),
                .product(
                    name:"OpenAL",
                    package: "swift-openal-soft"),
                ],
            exclude: [],
            cSettings: [
                .define("VK_USE_PLATFORM_WIN32_KHR",   .when(platforms:[.windows])),
                .define("VK_USE_PLATFORM_ANDROID_KHR", .when(platforms:[.android])),
                .define("VK_USE_PLATFORM_WAYLAND_KHR", .when(platforms:[.linux])),
                //.unsafeFlags(["-ISupportPackages/DKGame-ThirdParty/Sources/FreeType/include"]),
            ],
            swiftSettings: [
                // App & Window
                .define("ENABLE_WIN32",     .when(platforms: [.windows])),
                .define("ENABLE_UIKIT",     .when(platforms: [.iOS, .macCatalyst, .tvOS, .watchOS])),
                .define("ENABLE_APPKIT",    .when(platforms: [.macOS])),
                .define("ENABLE_WAYLAND",   .when(platforms: [.linux])),
                // Graphics Device
                .define("ENABLE_VULKAN",    .when(platforms: [.windows, .linux, .android])),
                .define("ENABLE_METAL",     .when(platforms: [.iOS, .macOS, .macCatalyst, .tvOS, .watchOS])),

                // Vulkan platforms
                .define("VK_USE_PLATFORM_WIN32_KHR",   .when(platforms:[.windows])),
                .define("VK_USE_PLATFORM_ANDROID_KHR", .when(platforms:[.android])),
                .define("VK_USE_PLATFORM_WAYLAND_KHR", .when(platforms:[.linux])),
            ],
            linkerSettings: [
                .linkedLibrary("User32",    .when(platforms: [.windows])),
                .linkedLibrary("Ole32",     .when(platforms: [.windows])),
                .linkedLibrary("Imm32",     .when(platforms: [.windows])),
                .linkedLibrary("Shcore",    .when(platforms: [.windows])),

                .linkedLibrary("SupportPackages/Vulkan/libs/Win32/x86_64/vulkan-1", .when(platforms: [.windows])),

                .unsafeFlags([
                    "-LSupportPackages/Vulkan/libs/Linux/x86_64",
                    "-lvulkan",
                    "-lwayland-client"
                ], .when(platforms: [.linux])),
            ]),
        .target(
            name: "DKGUI",
            dependencies: [
                .target(name: "DKGame"),
            ],
            exclude: [
                "Resources/Shaders/GLSL",
                "Resources/Shaders/gen_spv.py"
            ],
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/Shaders/SPIRV")
            ]),
        .executableTarget(
            name: "DKGameEditor",
            dependencies: [
                .target(name: "DKGame"),
                .target(name: "DKGUI"),
            ]),
        .testTarget(
            name: "DKGameTests",
            dependencies: [
                .target(name: "DKGame"),
            ]),
        .executableTarget(
            name: "TestApp1",
            dependencies: [
                .target(name: "DKGame"),
                .target(name: "DKGUI")
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: []),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx20
)
