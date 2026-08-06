//
//  File: MenuIndicator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

private struct MenuIndicatorVisibilityKey: EnvironmentKey {
    static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    public var menuIndicatorVisibility: Visibility {
        get { self[MenuIndicatorVisibilityKey.self] }
        set { self[MenuIndicatorVisibilityKey.self] = newValue }
    }
}

extension View {
    public func menuIndicator(_ visibility: Visibility) -> some View {
        environment(\.menuIndicatorVisibility, visibility)
    }
}
