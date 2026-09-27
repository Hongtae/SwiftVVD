// swift-tools-version: 6.4

import PackageDescription

let arch = {
#if arch(i386)
    return "i386"
#elseif arch(x86_64)
    return "x86_64"
#elseif arch(arm)
    return "arm"
#elseif arch(arm64)
    return "aarch64"
#else
    return "unknown"
#endif
}()

// Keep linker search paths independent of the consuming package's directory.
let vulkanLibraryPath = "\(Context.packageDirectory)/../../SupportPackages/Vulkan/lib"

let package = Package(
    name: "VVD",
    defaultLocalization: "en",
    platforms: [.macOS(.v27), .iOS(.v27), .macCatalyst(.v27)],
    products: [
        .library(name: "VVD", type: .dynamic, targets: ["VVD"]),
    ],
    dependencies: [
        .package(name: "VVDSupport", path: "../../SupportPackages/VVDSupport"),
        .package(name: "SPIRV-Cross", path: "../../SupportPackages/SPIRV-Cross"),
        .package(name: "FreeType", path: "../../SupportPackages/FreeType"),
        .package(name: "HarfBuzz", path: "../../SupportPackages/HarfBuzz"),
        .package(name: "miniaudio", path: "../../SupportPackages/miniaudio"),
        .package(name: "Vulkan", path: "../../SupportPackages/Vulkan"),
        .package(name: "Wayland", path: "../../SupportPackages/Wayland"),
    ],
    targets: [
        .target(
            name: "VVD",
            dependencies: [
                .product(name: "ICUTextAnalysis", package: "VVDSupport"),
                .product(name: "VVDSupport", package: "VVDSupport"),
                .product(name: "SPIRV-Cross", package: "SPIRV-Cross"),
                .product(name: "FreeType", package: "FreeType"),
                .product(name: "HarfBuzz", package: "HarfBuzz"),
                .product(name: "miniaudio", package: "miniaudio"),
                .product(
                    name: "Vulkan",
                    package: "Vulkan",
                    condition: .when(platforms: [.windows, .linux, .android])
                ),
                .product(
                    name: "Wayland",
                    package: "Wayland",
                    condition: .when(platforms: [.linux])
                ),
            ],
            path: "Sources",
            packageAccess: false,
            cSettings: [
                .define("VK_USE_PLATFORM_WIN32_KHR", .when(platforms: [.windows])),
                .define("VK_USE_PLATFORM_ANDROID_KHR", .when(platforms: [.android])),
                .define("VK_USE_PLATFORM_WAYLAND_KHR", .when(platforms: [.linux])),
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"]),
                // Preserve package access across the repository's shared-library packages.
                .unsafeFlags(["-package-name", "swiftvvd"]),
                .define("ENABLE_WIN32", .when(platforms: [.windows])),
                .define("ENABLE_UIKIT", .when(platforms: [.iOS, .macCatalyst, .tvOS, .watchOS])),
                .define("ENABLE_APPKIT", .when(platforms: [.macOS])),
                .define("ENABLE_WAYLAND", .when(platforms: [.linux])),
                .define("ENABLE_VULKAN", .when(platforms: [.windows, .linux, .android])),
                .define("ENABLE_METAL", .when(platforms: [.iOS, .macOS, .macCatalyst, .tvOS, .watchOS])),
                .define("VK_USE_PLATFORM_WIN32_KHR", .when(platforms: [.windows])),
                .define("VK_USE_PLATFORM_ANDROID_KHR", .when(platforms: [.android])),
                .define("VK_USE_PLATFORM_WAYLAND_KHR", .when(platforms: [.linux])),
            ],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS, .macCatalyst, .tvOS, .watchOS])),
                .linkedFramework("Metal", .when(platforms: [.macOS, .iOS, .macCatalyst, .tvOS, .watchOS])),
                .linkedLibrary("User32", .when(platforms: [.windows])),
                .linkedLibrary("Ole32", .when(platforms: [.windows])),
                .linkedLibrary("Imm32", .when(platforms: [.windows])),
                .linkedLibrary("Shcore", .when(platforms: [.windows])),
                .unsafeFlags(["-L\(vulkanLibraryPath)/Win32/\(arch)"], .when(platforms: [.windows])),
                .linkedLibrary("vulkan-1", .when(platforms: [.windows])),
                .unsafeFlags(["-L\(vulkanLibraryPath)/Linux/\(arch)"], .when(platforms: [.linux])),
                .linkedLibrary("vulkan", .when(platforms: [.linux])),
                .linkedLibrary("wayland-client", .when(platforms: [.linux])),
                .linkedLibrary("wayland-cursor", .when(platforms: [.linux])),
                .linkedLibrary("xkbcommon", .when(platforms: [.linux])),
            ]
        ),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx20
)
