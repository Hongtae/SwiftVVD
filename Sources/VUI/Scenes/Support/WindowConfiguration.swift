//
//  File: WindowConfiguration.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Runtime rendering configuration for a window.
struct WindowConfiguration {
    enum BackgroundRole: Equatable, Sendable {
        case window
        case content
        case fixed
    }

    var activeFrameInterval = 1.0 / 60.0
    var inactiveFrameInterval = 1.0 / 30.0
    // Windows synchronize presentation to the display unless a scene opts out.
    var displaySyncEnabled = true
    var drawEveryFrames: Bool = true
    private(set) var backgroundRole: BackgroundRole = .window
    private(set) var backgroundColor = BackendColor(white: 1)
    var drawDebugInfo: _DrawDebug.Info = []
    var drawDebugInfoPlacement = DebugInfoPlacement()
    var contentScaleFactorOverride: CGFloat? = nil

    mutating func setBackgroundRole(
        _ role: BackgroundRole,
        environment: EnvironmentValues
    ) {
        backgroundRole = role
        updateBackground(in: environment)
    }

    mutating func setFixedBackgroundColor(_ color: BackendColor) {
        backgroundRole = .fixed
        backgroundColor = color
    }

    mutating func updateBackground(in environment: EnvironmentValues) {
        let white: Double
        switch backgroundRole {
        case .window:
            white = environment.colorScheme.windowBackgroundWhite
        case .content:
            white = environment.colorScheme.contentBackgroundWhite(
                contrast: environment.colorSchemeContrast
            )
        case .fixed:
            return
        }
        backgroundColor = BackendColor(white: white)
    }

    // Partial values supplied by scene modifiers. nil means that the base
    // configuration remains in effect for that field.
    struct Override {
        var activeFrameInterval: Double? = nil
        var inactiveFrameInterval: Double? = nil
        var displaySyncEnabled: Bool? = nil
        var drawEveryFrames: Bool? = nil
        var backgroundColor: BackendColor? = nil
        var drawDebugInfo: _DrawDebug.Info? = nil
        var drawDebugInfoPlacement: DebugInfoPlacement? = nil
        var contentScaleFactor: CGFloat? = nil
    }

    func applying(_ override: Override) -> Self {
        var result = self
        if let value = override.activeFrameInterval {
            result.activeFrameInterval = value
        }
        if let value = override.inactiveFrameInterval {
            result.inactiveFrameInterval = value
        }
        if let value = override.displaySyncEnabled {
            result.displaySyncEnabled = value
        }
        if let value = override.drawEveryFrames {
            result.drawEveryFrames = value
        }
        if let value = override.backgroundColor {
            result.setFixedBackgroundColor(value)
        }
        if let value = override.drawDebugInfo {
            result.drawDebugInfo = value
        }
        if let value = override.drawDebugInfoPlacement {
            result.drawDebugInfoPlacement = value
        }
        if let value = override.contentScaleFactor {
            result.contentScaleFactorOverride = value
        }
        return result
    }
}

// Preference channel carrying runtime window overrides from the scene tree.
extension WindowConfiguration.Override {
    struct Key: PreferenceKey {
        static var defaultValue: WindowConfiguration.Override { .init() }

        static func reduce(
            value: inout WindowConfiguration.Override,
            nextValue: () -> WindowConfiguration.Override
        ) {
            let next = nextValue()
            if let nextValue = next.activeFrameInterval {
                value.activeFrameInterval = nextValue
            }
            if let nextValue = next.inactiveFrameInterval {
                value.inactiveFrameInterval = nextValue
            }
            if let nextValue = next.displaySyncEnabled {
                value.displaySyncEnabled = nextValue
            }
            if let nextValue = next.drawEveryFrames {
                value.drawEveryFrames = nextValue
            }
            if let nextValue = next.backgroundColor {
                value.backgroundColor = nextValue
            }
            if let nextValue = next.drawDebugInfo {
                if var combined = value.drawDebugInfo {
                    combined.formUnion(nextValue)
                    value.drawDebugInfo = combined
                } else {
                    value.drawDebugInfo = nextValue
                }
            }
            if let nextValue = next.drawDebugInfoPlacement {
                value.drawDebugInfoPlacement = nextValue
            }
            if let nextValue = next.contentScaleFactor {
                value.contentScaleFactor = nextValue
            }
        }
    }
}
