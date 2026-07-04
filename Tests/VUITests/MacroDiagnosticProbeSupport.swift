import Foundation
import XCTest

#if os(macOS)
func runMacroDiagnosticProbe(named name: String, source: String) throws -> String {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let buildRoot = packageRoot.appendingPathComponent(".build/debug")
    let descriptionURL = buildRoot.appendingPathComponent("description.json")
    let arguments = try swiftcArguments(from: descriptionURL, buildRoot: buildRoot)

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
