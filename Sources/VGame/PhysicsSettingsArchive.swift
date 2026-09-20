//
//  PhysicsSettingsArchive.swift
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Internal physics-settings format shared by game runtime and editor.
/// External asset conversion and packaging are separate VEditor operations.
public enum PhysicsSettingsArchive {
    public enum FormatError: Error {
        case unsupportedVersion(Int)
    }

    public static func encode(_ configuration: ScenePhysicsConfiguration) throws -> Data {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(version: 1, configuration: configuration))
    }

    public static func decode(_ data: Data) throws -> ScenePhysicsConfiguration {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1 else { throw FormatError.unsupportedVersion(document.version) }
        try document.configuration.validate()
        return document.configuration
    }

    public static func save(_ configuration: ScenePhysicsConfiguration, to url: URL) throws {
        let data = try encode(configuration)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> ScenePhysicsConfiguration {
        try decode(Data(contentsOf: url))
    }

    private struct Document: Codable {
        let version: Int
        let configuration: ScenePhysicsConfiguration
    }
}
