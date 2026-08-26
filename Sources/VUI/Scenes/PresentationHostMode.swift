//
//  File: PresentationHostMode.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Selects the default host surface for transient presentations in a scene.
public enum PresentationHostMode: Equatable, Sendable {
    /// Presents transient content inside the root window's render surface.
    case overlay

    /// Presents transient content in separate platform windows.
    case platformWindow
}

private struct DefaultPresentationHostModeKey: EnvironmentKey {
    static let defaultValue: PresentationHostMode = .overlay
}

extension EnvironmentValues {
    // Scene roots seed this value before view-level presentation overrides are
    // resolved. Presentation-specific keys may replace it at the source site.
    var defaultPresentationHostMode: PresentationHostMode {
        get { self[DefaultPresentationHostModeKey.self] }
        set { self[DefaultPresentationHostModeKey.self] = newValue }
    }

    /// Resolves an optional presentation-specific override before falling back
    /// to the Scene-wide default. Omitting the key path resolves only the default.
    func resolvedUsesPlatformWindow(
        _ overrideKeyPath: KeyPath<EnvironmentValues, Bool?>? = nil
    ) -> Bool {
        if let overrideKeyPath,
           let override = self[keyPath: overrideKeyPath] {
            return override
        }
        return defaultPresentationHostMode == .platformWindow
    }
}

extension Scene {
    /// Sets the default host surface for modal and popup presentations.
    public func defaultPresentationHostMode(
        _ mode: PresentationHostMode
    ) -> some Scene {
        modifier(TransformSceneListModifier { items in
            for index in items.indices {
                items[index].sceneConfiguration.defaultPresentationHostMode = mode
            }
        })
    }
}
