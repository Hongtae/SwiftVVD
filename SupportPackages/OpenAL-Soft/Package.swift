// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let cxxSettings: [CXXSetting] = [
    .headerSearchPath("openal-soft/alc"),
    .headerSearchPath("openal-soft/common"),
    .headerSearchPath("openal-soft/include"),
    .headerSearchPath("openal-soft"),
    .headerSearchPath("build"),

    .define("NOMINMAX", .when(platforms: [.windows])),
    .define("_CRT_SECURE_NO_WARNINGS", .when(platforms: [.windows])),
    .define("_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH", .when(platforms:[.windows])),
    .define("RESTRICT", to: "__restrict"),

    // FIXME: temporarily disable Xcode code coverage to prevent linker errors.
    .unsafeFlags(["-fno-profile-instr-generate", "-fno-coverage-mapping"], .when(platforms: applePlatforms, configuration: .debug)),
]

// The Xcode version of PackageDescription only recognizes Linux as
// a non-Apple platform, not Windows, but unfortunately I have not yet found
// a way to distinguish between SwiftPM and Xcode when building on a Mac.
// Until Xcode's version of PackageDescription is updated to recognize Windows,
// this seems to be the only way to build with Xcode.
var windowsOnly: TargetDependencyCondition {
#if os(Windows) || os(Linux)    // SwiftPM
    return .when(platforms: [.windows])
#else   // Xcode or SwiftPM (unable to identify)
    return .when(platforms: [.windows, .linux])
#endif
}
var androidOnly: TargetDependencyCondition {
#if os(Windows) || os(Linux)    // SwiftPM
    return .when(platforms: [.android])
#else   // Xcode or SwiftPM (unable to identify)
    return .when(platforms: [.android, .linux])
#endif
}

var mixer_simd_sources: [String] {
#if arch(i386) || arch(x86_64)
    [
        "openal-soft/core/mixer/mixer_sse.cpp",
        "openal-soft/core/mixer/mixer_sse2.cpp",
        "openal-soft/core/mixer/mixer_sse3.cpp",
        "openal-soft/core/mixer/mixer_sse41.cpp",
    ]
#elseif arch(arm) || arch(arm64)
    [
        "openal-soft/core/mixer/mixer_neon.cpp"
    ]
#else
    []
#endif
}

let applePlatforms: [Platform] = [.macOS, .iOS, .macCatalyst, .tvOS, .watchOS]

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

                .target(name: "OpenAL_backend_windows", condition: windowsOnly),
                .target(name: "OpenAL_backend_dsound", condition: windowsOnly),

                .target(name: "OpenAL_backend_coreaudio", condition: .when(platforms: applePlatforms)),

                .target(name: "OpenAL_backend_alsa", condition: .when(platforms: [.linux])),
                //.target(name: "OpenAL_backend_pulseaudio", condition: .when(platforms: [.linux])),
                //.target(name: "OpenAL_backend_pipewire", condition: .when(platforms: [.linux])),
                .target(name: "OpenAL_backend_oss", condition: .when(platforms: [.linux, .android])),
                .target(name: "OpenAL_backend_opensl", condition: androidOnly),

                .target(name: "OpenAL_mixer"),
            ],
            path: ".",
            exclude: [
                "openal-soft/alc/backends",
                "openal-soft/core/mixer",
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

                .linkedFramework("CoreFoundation", .when(platforms: applePlatforms)),
            ]),
        .target(
            name: "OpenAL_mixer",
            path: ".",
            sources: [
                "openal-soft/core/mixer/mixer_c.cpp",
            ] + mixer_simd_sources,
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings),
        .target(
            name: "OpenAL_backend",
            path: ".",
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
            path: ".",
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
            path: ".",
            sources: [
                "openal-soft/alc/backends/dsound.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings,
            linkerSettings: []),
        .target(
            name: "OpenAL_backend_coreaudio",
            path: ".",
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
            path: ".",
            sources: [
                "openal-soft/alc/backends/alsa.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings,
            linkerSettings: []),
        .target(
            name: "OpenAL_backend_pulseaudio",
            path: ".",
            sources: [
                "openal-soft/alc/backends/pulseaudio.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings,
            linkerSettings: []),
        .target(
            name: "OpenAL_backend_pipewire",
            path: ".",
            sources: [
                "openal-soft/alc/backends/pipewire.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings,
            linkerSettings: []),
        .target(
            name: "OpenAL_backend_oss",
            path: ".",
            sources: [
                "openal-soft/alc/backends/oss.cpp",
            ],
            publicHeadersPath: "swift_module",
            cxxSettings: cxxSettings,
            linkerSettings: []),
        .target(
            name: "OpenAL_backend_opensl",
            path: ".",
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
