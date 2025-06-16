//
//  File: FixedSizeLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _FixedSizeLayout: ViewModifier, Animatable {
    @inlinable public init(horizontal: Bool = true, vertical: Bool = true) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    @usableFromInline var horizontal: Bool
    @usableFromInline var vertical: Bool

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension View {
    @inlinable public func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        return modifier(
            _FixedSizeLayout(horizontal: horizontal, vertical: vertical))
    }

    @inlinable public func fixedSize() -> some View {
        return fixedSize(horizontal: true, vertical: true)
    }
}
