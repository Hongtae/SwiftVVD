// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FreeType",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "FreeType",
            type: .static,
            targets: [
                "FreeType"
                ]
            ),
    ],
    dependencies: [
        .package(
            name: "VVDSupport",
            path: "../VVDSupport"),
    ],
    targets: [
        .target(
            name: "FreeType",
            dependencies: [
                .product(name: "VVDSupport", package: "VVDSupport"),
            ],
            path: ".",
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
            publicHeadersPath: "include",
            cSettings: [
                .define("_CRT_SECURE_NO_WARNINGS", .when(platforms:[.windows])),
                .define("FT2_BUILD_LIBRARY"),
                .define("FT_DEBUG_LEVEL_ERROR", .when(configuration:.debug)),
                .define("FT_DEBUG_LEVEL_TRACE", .when(configuration:.debug)),
                .headerSearchPath("include"),
                .unsafeFlags([
                    "-Wno-format"
                ]),
            ]),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx17
)