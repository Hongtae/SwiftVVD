//
//  File: AnimationModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _AnimationModifier<Value>: ViewModifier where Value: Equatable {
    public var animation: Animation?
    public var value: Value

    @inlinable public init(animation: Animation?, value: Value) {
        self.animation = animation
        self.value = value
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError()
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        fatalError()
    }

    public typealias Body = Never
}

extension _AnimationModifier: Equatable {
}

extension View {
    @inlinable public func animation<V>(_ animation: Animation?, value: V) -> some View where V: Equatable {
        return modifier(_AnimationModifier(animation: animation, value: value))
    }
}

extension View where Self: Equatable {
    @inlinable public func animation(_ animation: Animation?) -> some View {
        return _AnimationView(content: self, animation: animation)
    }
}
