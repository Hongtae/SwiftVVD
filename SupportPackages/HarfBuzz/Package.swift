// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HarfBuzz",
    products: [
        .library(
            name: "HarfBuzz",
            type: .static,
            targets: ["HarfBuzz"]
        ),
    ],
    dependencies: [
        .package(name: "FreeType", path: "../FreeType"),
    ],
    targets: [
        .target(
            name: "HarfBuzz",
            dependencies: [
                .product(name: "FreeType", package: "FreeType"),
            ],
            path: "Sources/HarfBuzz",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("HAVE_FREETYPE", to: "1"),
                .define("HAVE_FT_DONE_MM_VAR", to: "1"),
                .define("HAVE_FT_GET_TRANSFORM", to: "1"),
                .define("HAVE_FT_GET_VAR_BLEND_COORDINATES", to: "1"),
                .define("HAVE_FT_SET_VAR_BLEND_COORDINATES", to: "1"),
                .define("_CRT_SECURE_NO_WARNINGS", .when(platforms: [.windows])),
                .define("_CRT_NONSTDC_NO_WARNINGS", .when(platforms: [.windows])),
            ]
        ),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx14
)
