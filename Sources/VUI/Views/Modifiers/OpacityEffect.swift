//
//  File: OpacityEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _OpacityEffect: ViewModifier {
    public var opacity: Double
    
    @inlinable public init(opacity: Double) {
        self.opacity = opacity
    }

    public typealias Body = Never

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        // TODO: Actually apply opacity to the display list.
        // For now, this is a pass-through stub to allow compilation and structural equivalence.
        return body(_Graph(), inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        // TODO: Actually apply opacity to the display list.
        // For now, this mirrors _makeView so list-based collection can pass through.
        return body(_Graph(), inputs)
    }
}

extension View {
    @inlinable public func opacity(_ opacity: Double) -> some View {
        modifier(_OpacityEffect(opacity: opacity))
    }
}
