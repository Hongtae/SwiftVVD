//
//  File: OverlayModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _OverlayModifier<Overlay>: ViewModifier where Overlay: View {
    public typealias Body = Never

    public let overlay: Overlay
    public let alignment: Alignment

    @inlinable public init(overlay: Overlay, alignment: Alignment = .center) {
        self.overlay = overlay
        self.alignment = alignment
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        inputs.modifiers[ObjectIdentifier(Self.self)] = modifier.value
        return body(_Graph(), inputs)
    }
}

extension _OverlayModifier: Equatable where Overlay: Equatable {
}

extension View {
    @inlinable public func overlay<Overlay>(_ overlay: Overlay, alignment: Alignment = .center) -> some View where Overlay: View {
        return modifier(_OverlayModifier(overlay: overlay, alignment: alignment))
    }

    @inlinable public func border<S>(_ content: S, width: CGFloat = 1) -> some View where S: ShapeStyle {
        return overlay(Rectangle().strokeBorder(content, lineWidth: width))
    }
}
