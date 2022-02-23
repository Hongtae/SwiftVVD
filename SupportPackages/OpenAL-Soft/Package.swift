// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let cxxSettings: [CXXSetting] = [
    .headerSearchPath("openal-soft/alc"),
    .headerSearchPath("openal-soft/build"),
    .headerSearchPath("openal-soft/common"),
    .headerSearchPath("openal-soft/include"),
    .headerSearchPath("openal-soft"),
]

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
                .target(name: "OpenAL_backend"),
                .target(name: "OpenAL_backend_windows", condition:.when(platforms: [.windows])),
                .target(name: "OpenAL_backend_coreaudio", condition:.when(platforms: [.macOS, .iOS, .tvOS])),
                .target(name: "OpenAL_mixer_sse", condition:.when(platforms: [.windows])),
                .target(name: "OpenAL_mixer_neon", condition:.when(platforms: [.iOS, .tvOS])),
                ],
            path: "Sources",
            exclude: [
                "openal-soft/alc/backends",
                "openal-soft/core/mixer/mixer_sse.cpp",
                "openal-soft/core/mixer/mixer_sse2.cpp",
                "openal-soft/core/mixer/mixer_sse3.cpp",
                "openal-soft/core/mixer/mixer_sse41.cpp", 
                "openal-soft/core/mixer/mixer_neon.cpp",               
            ],
            sources: [
                "openal-soft/common",
                "openal-soft/al",
                "openal-soft/alc",
                "openal-soft/core",
            ],
            publicHeadersPath: "openal-soft/include",
            cxxSettings: cxxSettings + [
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
            name: "OpenAL_mixer_sse",
            path: "Sources",
            sources: [
                "openal-soft/core/mixer/mixer_sse.cpp",
                "openal-soft/core/mixer/mixer_sse2.cpp",
                "openal-soft/core/mixer/mixer_sse3.cpp",
                "openal-soft/core/mixer/mixer_sse41.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings),
        .target(
            name: "OpenAL_mixer_neon",
            path: "Sources",
            sources: [
                "openal-soft/core/mixer/mixer_neon.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings),
        .target(
            name: "OpenAL_backend",
            path: "Sources",
            sources: [
                "openal-soft/alc/backends/loopback.cpp",
                "openal-soft/alc/backends/base.cpp",
                "openal-soft/alc/backends/null.cpp",
                "openal-soft/alc/backends/wave.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings),
        .target(
            name: "OpenAL_backend_windows",
            path: "Sources",
            sources: [
                "openal-soft/alc/backends/dsound.cpp",
                "openal-soft/alc/backends/winmm.cpp",
                "openal-soft/alc/backends/wasapi.cpp"
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings),
        .target(
            name: "OpenAL_backend_coreaudio",
            path: "Sources",
            sources: [
                "openal-soft/alc/backends/coreaudio.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings)

    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx20
)
