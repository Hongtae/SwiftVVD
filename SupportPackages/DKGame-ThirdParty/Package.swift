// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DKGame-ThirdParty",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "DKGame-ThirdParty",
            targets: [
                "DKGameSupport",
                "FreeType",
                "zlib",
                "cpp_test"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DKGameSupport",
            dependencies: []),
        .target(
            name: "FreeType",
            path: "Sources/FreeType",
            sources: [
                "src/autofit/autofit.c",
                "src/base/ftbase.c",
                "src/base/ftbbox.c",
                "src/base/ftbdf.c",
                "src/base/ftbitmap.c",
                "src/base/ftcid.c",
                "src/base/ftdebug.c",
                "src/base/ftfntfmt.c",
                "src/base/ftfstype.c",
                "src/base/ftgasp.c",
                "src/base/ftglyph.c",
                "src/base/ftgxval.c",
                "src/base/ftinit.c",
                "src/base/ftlcdfil.c",
                "src/base/ftmm.c",
                "src/base/ftotval.c",
                "src/base/ftpatent.c",
                "src/base/ftpfr.c",
                "src/base/ftstroke.c",
                "src/base/ftsynth.c",
                "src/base/ftsystem.c",
                "src/base/fttype1.c",
                "src/base/ftwinfnt.c",
                "src/bdf/bdf.c",
                "src/cache/ftcache.c",
                "src/cff/cff.c",
                "src/cid/type1cid.c",
                "src/gzip/ftgzip.c",
                "src/lzw/ftlzw.c",
                "src/pcf/pcf.c",
                "src/pfr/pfr.c",
                "src/psaux/psaux.c",
                "src/pshinter/pshinter.c",
                "src/psnames/psmodule.c",
                "src/raster/raster.c",
                "src/sfnt/sfnt.c",
                "src/smooth/smooth.c",
                "src/truetype/truetype.c",
                "src/type1/type1.c",
                "src/type42/type42.c",
                "src/winfonts/winfnt.c"],
            publicHeadersPath: "public",
            cSettings: [
                .define("_CRT_SECURE_NO_WARNINGS", .when(platforms:[.windows])),
                .define("FT2_BUILD_LIBRARY"),
                .define("FT_DEBUG_LEVEL_ERROR", .when(configuration:.debug)),
                .define("FT_DEBUG_LEVEL_TRACE", .when(configuration:.debug)),
                .headerSearchPath("include"),
            ]),
        .target(
            name: "zlib",
            path: "Sources/zlib",
            sources: [
                "src/adler32.c",
                "src/compress.c",
                "src/crc32.c",
                "src/deflate.c",
                "src/gzclose.c",
                "src/gzlib.c",
                "src/gzread.c",
                "src/gzwrite.c",
                "src/infback.c",
                "src/inffast.c",
                "src/inflate.c",
                "src/inftrees.c",
                "src/trees.c",
                "src/uncompr.c",
                "src/zutil.c"],
            publicHeadersPath: "include"),
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
