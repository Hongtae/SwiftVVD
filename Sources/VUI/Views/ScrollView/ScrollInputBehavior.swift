//
//  File: ScrollInputBehavior.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// A policy that controls whether a particular kind of input can scroll a view.
public struct ScrollInputBehavior: Sendable, Equatable {
    private enum Storage: Hashable, Sendable {
        case automatic
        case enabled
        case disabled
    }

    private var storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    public static let automatic = ScrollInputBehavior(storage: .automatic)
    public static let enabled = ScrollInputBehavior(storage: .enabled)
    public static let disabled = ScrollInputBehavior(storage: .disabled)
}

/// A category of input that can drive scrolling.
public struct ScrollInputKind: Sendable, Equatable {
    private enum Storage: Equatable, Sendable {
        case look(axes: Axis.Set?)
        case handGestureShortcut
    }

    private var storage: Storage
}

extension View {
    /// Sets the scrolling policy for a particular input category.
    @MainActor @preconcurrency
    public func scrollInputBehavior(
        _ behavior: ScrollInputBehavior,
        for input: ScrollInputKind
    ) -> some View {
        // This surface has no source-constructible input category, so the
        // configuration does not attach state to the view graph.
        self
    }
}
