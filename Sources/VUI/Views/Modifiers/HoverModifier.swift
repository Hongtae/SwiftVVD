//
//  File: HoverModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _HoverBackgroundModifier<Background>: ViewModifier where Background: View {
    public var background: Background

    @inlinable public init(background: Background) {
        self.background = background
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
}

extension _HoverBackgroundModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

public struct _HoverOverlayModifier<Overlay>: ViewModifier where Overlay: View {
    public var overlay: Overlay

    @inlinable public init(overlay: Overlay) {
        self.overlay = overlay
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
}

extension _HoverOverlayModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

public struct _HoverRegionModifier: ViewModifier {
    public var action: (Bool) -> Void

    @inlinable public init(_ action: @escaping (Bool) -> Void) {
        self.action = action
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
}

extension _HoverRegionModifier {
    public typealias Body = Never

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

extension View {
    @inlinable
    public func hoverBackground<V>(@ViewBuilder content: () -> V) -> some View where V: View {
        modifier(_HoverBackgroundModifier(background: content()))
    }

    @inlinable
    public func hoverOverlay<V>(@ViewBuilder content: () -> V) -> some View where V: View {
        modifier(_HoverOverlayModifier(overlay: content()))
    }

    @inlinable
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(_HoverRegionModifier(action))
    }
}
