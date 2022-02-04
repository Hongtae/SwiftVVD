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
        .package(
            name: "DKGame-ThirdParty",
            path: "SupportPackages/DKGame-ThirdParty"),
        .package(
            name: "Vulkan",
            path: "SupportPackages/Vulkan"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "DKGame",
            dependencies: [
                .product(
                    name: "DKGame-ThirdParty",
                    package:"DKGame-ThirdParty"),
                .product(
                    name: "Vulkan",
                    package:"Vulkan",
                    condition: .when(platforms: [.windows, .linux, .android])),
                ],
            exclude: [],
            cSettings: [
                .unsafeFlags(["-ISupportPackages/DKGame-ThirdParty/Sources/FreeType/include"]),
            ],
            linkerSettings: [
                .linkedLibrary("User32", .when(platforms: [.windows])),
                .linkedLibrary("Ole32",  .when(platforms: [.windows])),
                .linkedLibrary("Imm32",  .when(platforms: [.windows])),
                .linkedLibrary("Shcore", .when(platforms: [.windows])),
                .linkedLibrary("SupportPackages/Vulkan/lib/Win32/vulkan-1", .when(platforms: [.windows])),
                // .unsafeFlags([
                //     "-LSupportPackages/Vulkan/lib/Win32"
                //     ], .when(platforms: [.windows]))
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
                ],
            linkerSettings: []),
    ]
)
