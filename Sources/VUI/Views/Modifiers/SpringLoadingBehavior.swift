//
//  File: SpringLoadingBehavior.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct SpringLoadingBehavior: Hashable, Sendable {
    private enum Guts: UInt8, Hashable, Sendable {
        case automatic
        case enabled
        case disabled
    }

    private var guts: Guts

    private init(guts: Guts) {
        self.guts = guts
    }

    public static let automatic = Self(guts: .automatic)
    public static let enabled = Self(guts: .enabled)
    public static let disabled = Self(guts: .disabled)

    struct HasCustomSpringLoadedBehavior: ViewInputBoolFlag {}
}

private struct SpringLoadingBehaviorKey: EnvironmentKey {
    static let defaultValue: SpringLoadingBehavior = .automatic
}

extension EnvironmentValues {
    public internal(set) var springLoadingBehavior: SpringLoadingBehavior {
        get { self[SpringLoadingBehaviorKey.self] }
        set { self[SpringLoadingBehaviorKey.self] = newValue }
    }
}

extension View {
    public func springLoadingBehavior(
        _ behavior: SpringLoadingBehavior
    ) -> some View {
        environment(\.springLoadingBehavior, behavior)
            .input(SpringLoadingBehavior.HasCustomSpringLoadedBehavior.self)
    }
}
