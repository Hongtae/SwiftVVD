//
//  File: Prominence.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public enum Prominence: Hashable, Sendable {
    case standard
    case increased
}

private struct HeaderProminenceEnvironmentKey: EnvironmentKey {
    static var defaultValue: Prominence { .standard }
}

struct HeaderProminenceKey: _ViewTraitKey {
    static var defaultValue: Prominence { .standard }
}

extension EnvironmentValues {
    public var headerProminence: Prominence {
        get { self[HeaderProminenceEnvironmentKey.self] }
        set { self[HeaderProminenceEnvironmentKey.self] = newValue }
    }
}

extension View {
    public func headerProminence(_ prominence: Prominence) -> some View {
        environment(\.headerProminence, prominence)
            ._trait(HeaderProminenceKey.self, prominence)
    }
}
