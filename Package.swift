// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VVD",
    platforms: [.macOS(.v15), .iOS(.v18), .macCatalyst(.v18)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(name: "VVD", type: .dynamic, targets: ["VVD"]),
        .library(name: "XGUI", type: .dynamic, targets: ["XGUI"]),
        .executable(name: "Editor", targets: ["Editor"]),
        .executable(name: "TestApp1", targets: ["TestApp1"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "VVDSupport",
                 path: "SupportPackages/VVDSupport"),
        .package(name: "SPIRV-Cross",
                 path: "SupportPackages/SPIRV-Cross"),
        .package(name: "FreeType",
                 path: "SupportPackages/FreeType"),
        .package(name: "OpenAL-Soft",
                 path: "SupportPackages/OpenAL-Soft"),
        .package(name: "TinyGLTF",
                 path: "SupportPackages/TinyGLTF"),
        .package(name: "Vulkan",
                 path: "SupportPackages/Vulkan"),
        .package(name: "Wayland",
                 path: "SupportPackages/Wayland"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "VVD",
            dependencies: [
                .product(name: "VVDSupport",
                         package: "VVDSupport"),
                .product(name: "SPIRV-Cross",
                         package: "SPIRV-Cross"),
                .product(name: "FreeType",
                         package: "FreeType"),
                .product(name: "OpenAL",
                         package: "OpenAL-Soft"),
                .product(name: "Vulkan",
                         package: "Vulkan",
                         condition: .when(platforms: [.windows, .linux, .android])),
                .product(name: "Wayland",
                         package: "Wayland",
                         condition: .when(platforms: [.linux])),
                ],
            exclude: [],
            cSettings: [
                .define("VK_USE_PLATFORM_WIN32_KHR",   .when(platforms:[.windows])),
                .define("VK_USE_PLATFORM_ANDROID_KHR", .when(platforms:[.android])),
                .define("VK_USE_PLATFORM_WAYLAND_KHR", .when(platforms:[.linux])),
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
            name: "XGUI",
            dependencies: [
                .target(name: "VVD"),
            ],
            exclude: [
                "Resources/Shaders/GLSL",
                "Resources/Shaders/gen_spv.py"
            ],
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/Shaders/SPIRV")
            ],
            swiftSettings: [
            ]),
        .executableTarget(
            name: "Editor",
            dependencies: [
                .target(name: "VVD"),
                .target(name: "XGUI"),
            ]),
        .testTarget(
            name: "VVDTests",
            dependencies: [
                .target(name: "VVD"),
            ]),
        .executableTarget(
            name: "TestApp1",
            dependencies: [
                .target(name: "VVD"),
                .target(name: "XGUI")
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: []),
        .executableTarget(
            name: "RenderTest",
            dependencies: [
                .target(name: "VVD"),
                .product(name: "TinyGLTF",
                         package: "TinyGLTF"),
            ],
            resources: [
                .copy("Resources/Shaders"),
                .copy("Resources/glTF"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx20
)
