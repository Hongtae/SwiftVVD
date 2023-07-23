//
//  File: AlignmentWritingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _AlignmentWritingModifier: ViewModifier {
    @usableFromInline
    let key: AlignmentKey
    @usableFromInline
    let computeValue: (ViewDimensions) -> CGFloat

    @inlinable init(key: AlignmentKey, computeValue: @escaping (ViewDimensions) -> CGFloat) {
        self.key = key
        self.computeValue = computeValue
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError()
    }
    public typealias Body = Never
}

extension _AlignmentWritingModifier: _UnaryViewModifier {
}

extension View {
    @inlinable public func alignmentGuide(_ g: HorizontalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        return modifier(
            _AlignmentWritingModifier(key: g.key, computeValue: computeValue))
    }

    @inlinable public func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
        return modifier(
            _AlignmentWritingModifier(key: g.key, computeValue: computeValue))
    }
}
