//
//  File: EmptyModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public struct EmptyModifier: ViewModifier, Sendable {
    public typealias Body = Never
    public static let identity = EmptyModifier()

    public init() {}

    public static func _makeView(modifier: _GraphValue<EmptyModifier>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
    public static func _makeViewList(modifier: _GraphValue<EmptyModifier>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }

    public func body(content: Self.Content) -> Self.Body {
        fatalError("\(Self.self) may not have Body == Never")
    }
}
