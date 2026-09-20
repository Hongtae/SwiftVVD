//
//  PhysicsSettingsDraft.swift
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VGame

/// Editable settings for an inspector, command-line tool, or scene asset.
/// Editing and loading a draft never changes a running world until `apply`.
struct PhysicsSettingsDraft: Sendable {
    var configuration: ScenePhysicsConfiguration

    init(configuration: ScenePhysicsConfiguration = .default) {
        self.configuration = configuration
    }

    mutating func selectPreset(_ preset: ScenePhysicsConfiguration.Preset) {
        configuration = preset.configuration
    }

    func apply(to physics: WorldPhysics) throws {
        try physics.apply(configuration)
    }

    func encoded() throws -> Data {
        try PhysicsSettingsArchive.encode(configuration)
    }

    /// Reject unsupported versions or invalid values before replacing the draft.
    mutating func load(_ data: Data) throws {
        configuration = try PhysicsSettingsArchive.decode(data)
    }
}
