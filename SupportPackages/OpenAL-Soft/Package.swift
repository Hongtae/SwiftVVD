// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let cxxSettings: [CXXSetting] = [
    .headerSearchPath("openal-soft/alc"),
    .headerSearchPath("openal-soft/build"),
    .headerSearchPath("openal-soft/common"),
    .headerSearchPath("openal-soft/include"),
    .headerSearchPath("openal-soft"),

    .define("NOMINMAX", .when(platforms: [.windows])),
    .define("_CRT_SECURE_NO_WARNINGS", .when(platforms: [.windows])),
    .define("RESTRICT", to: "__restrict"),
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

                .target(name: "OpenAL_backend_windows", condition: .when(platforms: [.windows])),
                .target(name: "OpenAL_backend_dsound", condition: .when(platforms: [.windows])),
                .target(name: "OpenAL_backend_coreaudio", condition: .when(platforms: [.macOS, .iOS, .macCatalyst, .tvOS, .watchOS])),
                .target(name: "OpenAL_backend_alsa", condition: .when(platforms: [.linux, .android])),
                .target(name: "OpenAL_backend_oss", condition: .when(platforms: [.linux, .android])),
                .target(name: "OpenAL_backend_opensl", condition: .when(platforms: [.linux, .android])),

                .target(name: "OpenAL_mixer_sse", condition: .when(platforms: [.windows])),
                .target(name: "OpenAL_mixer_neon", condition: .when(platforms: [.macOS, .iOS, .macCatalyst, .tvOS, .watchOS])),
            ],
            path: "Sources",
            exclude: [
                "openal-soft/alc/backends",
                "openal-soft/core/mixer/mixer_sse.cpp",
                "openal-soft/core/mixer/mixer_sse2.cpp",
                "openal-soft/core/mixer/mixer_sse3.cpp",
                "openal-soft/core/mixer/mixer_sse41.cpp",
                "openal-soft/core/mixer/mixer_neon.cpp",
                "openal-soft/core/rtkit.cpp",
                "openal-soft/core/dbus_wrap.cpp",
            ],
            sources: [
                "openal-soft/common",
                "openal-soft/al",
                "openal-soft/alc",
                "openal-soft/core",
            ],
            publicHeadersPath: "openal-soft/include",
            cxxSettings: cxxSettings + [
                .define("AL_BUILD_LIBRARY"),
                .define("AL_ALEXT_PROTOTYPES"),

                .define("ALC_API", to: "__declspec(dllexport)", .when(platforms: [.windows])),
                .define("AL_API", to: "__declspec(dllexport)", .when(platforms: [.windows])),
                
                //.unsafeFlags(["-fms-extensions"], .when(platforms: [.windows])),
                .unsafeFlags(["-Wno-unused-value"]),
                .unsafeFlags(["-Oz"], .when(platforms: [.windows], configuration: .release)),
            ],
            linkerSettings: [
                .linkedLibrary("Shell32", .when(platforms: [.windows])),
                .linkedLibrary("Ole32", .when(platforms: [.windows])),
                .linkedLibrary("User32", .when(platforms: [.windows])),
                .linkedLibrary("Winmm", .when(platforms: [.windows])),
                .linkedLibrary("swiftCore", .when(platforms: [.windows])), // swift_addNewDSOImage

                .linkedFramework("CoreFoundation", .when(platforms: [.macOS, .iOS, .macCatalyst, .tvOS, .watchOS])),
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
                "openal-soft/alc/backends/winmm.cpp",
                "openal-soft/alc/backends/wasapi.cpp"
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings + [
                .unsafeFlags(["-Oz"], .when(platforms: [.windows], configuration: .release)),
            ]),
        .target(
            name: "OpenAL_backend_dsound",
            path: "Sources",
            sources: [
                "openal-soft/alc/backends/dsound.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings,
            linkerSettings: []),
        .target(
            name: "OpenAL_backend_coreaudio",
            path: "Sources",
            sources: [
                "openal-soft/alc/backends/coreaudio.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings + [
                .unsafeFlags(["-Wno-deprecated-anon-enum-enum-conversion"]),
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]),
        .target(
            name: "OpenAL_backend_alsa",
            path: "Sources",
            sources: [
                "openal-soft/alc/backends/alsa.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings,
            linkerSettings: []),
        .target(
            name: "OpenAL_backend_oss",
            path: "Sources",
            sources: [
                "openal-soft/alc/backends/oss.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings,
            linkerSettings: []),
        .target(
            name: "OpenAL_backend_opensl",
            path: "Sources",
            sources: [
                "openal-soft/alc/backends/opensl.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings,
            linkerSettings: []),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx20
)
