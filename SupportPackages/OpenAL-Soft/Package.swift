// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OepnAL-Soft",
    products: [
        .library(
            name: "OpenAL",
            type: .dynamic,
            targets: ["OpenAL"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OpenAL",
            dependencies: [
                .target(name: "backend"),
                .target(name: "backend_windows", condition:.when(platforms: [.windows])),
                .target(name: "mixer_sse", condition:.when(platforms: [.windows])),
                // .target(name: "mixer_neon", condition:.when(platforms: [.iOS])),
                ],
            path: "Sources",
            exclude: [
                "alc/backends",
                "core/mixer/mixer_sse.cpp",
                "core/mixer/mixer_sse2.cpp",
                "core/mixer/mixer_sse3.cpp",
                "core/mixer/mixer_sse41.cpp", 
                "core/mixer/mixer_neon.cpp",               
            ],
            sources: [
                "common",
                "al",
                "alc",
                "core",
            ],
            publicHeadersPath: "include",
            cSettings: [],
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("build"),
                .headerSearchPath("common"),
                .headerSearchPath("alc"),
                //.define("AL_ALEXT_PROTOTYPES"),
                //.unsafeFlags(["-fms-extensions"], .when(platforms: [.windows]))
                .unsafeFlags(["-Wno-unused-value"])
            ],
            linkerSettings: [
                .linkedLibrary("Shell32", .when(platforms: [.windows])),
                .linkedLibrary("Ole32", .when(platforms: [.windows])),
                .linkedLibrary("User32", .when(platforms: [.windows])),
                .linkedLibrary("Winmm", .when(platforms: [.windows])),
                .linkedLibrary("swiftCore"), // swift_addNewDSOImage
            ]),
        .target(
            name: "mixer_sse",
            path: "Sources",
            sources: [
                "core/mixer/mixer_sse.cpp",
                "core/mixer/mixer_sse2.cpp",
                "core/mixer/mixer_sse3.cpp",
                "core/mixer/mixer_sse41.cpp",
            ],
            publicHeadersPath: "build/swift_umbrella/mixer_sse",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("build"),
                .headerSearchPath("common"),
                ]),
        .target(
            name: "mixer_neon",
            path: "Sources",
            sources: [
                "core/mixer/mixer_neon.cpp",
            ],
            publicHeadersPath: "build/swift_umbrella/mixer_neon",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("build"),
                .headerSearchPath("common"),
                ]),
        .target(
            name: "backend",
            path: "Sources",
            sources: [
                "alc/backends/loopback.cpp",
                "alc/backends/base.cpp",
                "alc/backends/null.cpp",
                "alc/backends/wave.cpp",
            ],
            publicHeadersPath: "build/swift_umbrella/backend",
            cxxSettings: [
                .headerSearchPath("alc"),
                .headerSearchPath("build"),
                .headerSearchPath("common"),
                .headerSearchPath("include"),
                .headerSearchPath("."),
                ]),
        .target(
            name: "backend_windows",
            path: "Sources",
            sources: [
                "alc/backends/dsound.cpp",
                "alc/backends/winmm.cpp",
                "alc/backends/wasapi.cpp"
            ],
            publicHeadersPath: "build/swift_umbrella/backend_windows",
            cxxSettings: [
                .headerSearchPath("alc"),
                .headerSearchPath("build"),
                .headerSearchPath("common"),
                .headerSearchPath("include"),
                .headerSearchPath("."),
                ])
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx20
)
