import Foundation
import XCTest

#if os(macOS)
private final class MacroDiagnosticProbeBundleToken {}

func runMacroDiagnosticProbe(named name: String, source: String) throws -> String {
    // The SwiftPM build plan belongs to the package root, not the test bundle.
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let buildRoot = try macroDiagnosticBuildRoot(packageRoot: packageRoot)
    let descriptionURL = buildRoot.appendingPathComponent("description.json")
    let arguments: [String]
    if FileManager.default.fileExists(atPath: descriptionURL.path) {
        arguments = try swiftcArguments(
            from: descriptionURL,
            buildRoot: buildRoot
        )
    } else {
        arguments = try nativeBuildSwiftcArguments(
            packageRoot: packageRoot,
            buildRoot: buildRoot
        )
    }

    let sourceURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("vui_macro_\(name)_\(UUID().uuidString)")
        .appendingPathExtension("swift")
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftc", "-typecheck"] + arguments + [sourceURL.path]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    XCTAssertNotEqual(process.terminationStatus, 0, output)
    return output
}

private func macroDiagnosticBuildRoot(packageRoot: URL) throws -> URL {
    let bundleProductRoot = Bundle(for: MacroDiagnosticProbeBundleToken.self)
        .bundleURL
        .deletingLastPathComponent()
    let candidates = [
        bundleProductRoot,
        packageRoot.appendingPathComponent(".build/debug"),
        packageRoot.appendingPathComponent(".build/release"),
    ]
    return try XCTUnwrap(candidates.first { candidate in
        FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent("VUIMacros").path
        ) && FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent("VUI.swiftmodule").path
        )
    }, "Missing built VUIMacros and VUI products")
}

private func nativeBuildSwiftcArguments(
    packageRoot: URL,
    buildRoot: URL
) throws -> [String] {
    let plugin = buildRoot.appendingPathComponent("VUIMacros")
    let module = buildRoot.appendingPathComponent("VUI.swiftmodule")
    _ = try XCTUnwrap(
        FileManager.default.fileExists(atPath: plugin.path) ? plugin : nil,
        "Missing built VUIMacros plugin at \(plugin.path)"
    )
    _ = try XCTUnwrap(
        FileManager.default.fileExists(atPath: module.path) ? module : nil,
        "Missing built VUI module at \(module.path)"
    )

    var arguments = [
        "-dump-macro-expansions",
        "-I", buildRoot.path,
        "-load-plugin-executable", "\(plugin.path)#VUIMacros",
    ]
    let helperModuleMap = packageRoot
        .appendingPathComponent(".build/out/Intermediates.noindex/GeneratedModuleMaps/VVDHelper.modulemap")
    if FileManager.default.fileExists(atPath: helperModuleMap.path) {
        arguments.append(contentsOf: [
            "-Xcc", "-fmodule-map-file=\(helperModuleMap.path)",
        ])
    }
    return arguments
}

private func swiftcArguments(from descriptionURL: URL, buildRoot: URL) throws -> [String] {
    let data = try Data(contentsOf: descriptionURL)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let commands = try XCTUnwrap(root["swiftCommands"] as? [String: Any])
    let command = try XCTUnwrap(commands.first { key, _ in
        key.hasPrefix("C.VUITests-") && key.hasSuffix(".module")
    }?.value as? [String: Any])
    let rawArguments = try XCTUnwrap(command["otherArguments"] as? [String])

    let removeWithValue: Set<String> = [
        "-index-store-path",
        "-module-cache-path",
    ]
    let removeSingle: Set<String> = [
        "-incremental",
        "-enable-batch-mode",
        "-serialize-diagnostics",
        "-parseable-output",
        "-parse-as-library",
        "-j10",
    ]

    var arguments = ["-dump-macro-expansions"]
    var index = rawArguments.startIndex
    while index < rawArguments.endIndex {
        let argument = rawArguments[index]
        if removeWithValue.contains(argument) {
            index = rawArguments.index(index, offsetBy: 2, limitedBy: rawArguments.endIndex) ?? rawArguments.endIndex
        } else if removeSingle.contains(argument) {
            index = rawArguments.index(after: index)
        } else {
            arguments.append(argument)
            index = rawArguments.index(after: index)
        }
    }

    arguments.append(contentsOf: [
        "-I",
        buildRoot.appendingPathComponent("Modules").path,
    ])
    return arguments
}
#endif
