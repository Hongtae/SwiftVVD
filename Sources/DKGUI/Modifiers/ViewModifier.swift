//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct _ViewModifier_Content<Modifier> where Modifier: ViewModifier {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<_ViewModifier_Content<Modifier>>, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewOutputs()
    }
    public static func _makeViewList(view: _GraphValue<_ViewModifier_Content<Modifier>>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs()
    }
}

extension _ViewModifier_Content: View {
    public var body: Never { neverBody() }
}

public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder func body(content: Self.Content) -> Self.Body
    typealias Content = _ViewModifier_Content<Self>
}

extension ViewModifier where Self.Body == Never {
    public func body(content: Self.Content) -> Self.Body { neverBody() }
}

extension ViewModifier {
    public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

extension ViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        _ViewOutputs()
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        _ViewListOutputs()
    }
}
