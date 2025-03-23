// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SPIRV-Cross",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SPIRV-Cross",
            type: .static,
            targets: [
                "SPIRV-Cross", 
            ]
        ),
    ],
    targets: [
        .target(
            name: "SPIRV-Cross",
            path: "Sources",
            sources: [
                "spirv_cfg.cpp",
                "spirv_cpp.cpp",
                "spirv_cross.cpp",
                "spirv_cross_c.cpp",
                "spirv_cross_parsed_ir.cpp",
                "spirv_cross_util.cpp",
                "spirv_glsl.cpp",
                "spirv_hlsl.cpp",
                "spirv_msl.cpp",
                "spirv_parser.cpp",
                "spirv_reflect.cpp"],
            publicHeadersPath: ".",
            cxxSettings: [
                .define("SPIRV_CROSS_C_API_CPP", to: "1"),
                .define("SPIRV_CROSS_C_API_GLSL", to: "1"),
                .define("SPIRV_CROSS_C_API_HLSL", to: "1"),
                .define("SPIRV_CROSS_C_API_MSL", to: "1"),
                .define("SPIRV_CROSS_C_API_REFLECT", to: "1"),
                .define("_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH", .when(platforms:[.windows])),
            ]),
    ],
    cLanguageStandard: .c17,
    cxxLanguageStandard: .cxx17
)
