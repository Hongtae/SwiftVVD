//
//  File: TraitWritingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol _ViewTraitKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

public struct _TraitWritingModifier<Trait>: ViewModifier where Trait: _ViewTraitKey {
    public let value: Trait.Value
    public init(value: Trait.Value) {
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

extension View {
    public func _trait<K>(_ key: K.Type, _ value: K.Value) -> some View where K: _ViewTraitKey {
        return modifier(_TraitWritingModifier<K>(value: value))
    }
}
