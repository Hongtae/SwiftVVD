//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ViewModifier_Content<Modifier> where Modifier: ViewModifier {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

extension _ViewModifier_Content: View {
    public var body: Never { neverBody() }
}

private struct _ViewModifierBodyContext {
    struct _Body: @unchecked Sendable {
        let makeView: ((_Graph, _ViewInputs) -> _ViewOutputs)?
        let makeViewList: ((_Graph, _ViewListInputs) -> _ViewListOutputs)?
    }

    @TaskLocal
    static var body: [ObjectIdentifier: _Body] = [:]
}

public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder func body(content: Self.Content) -> Self.Body
    typealias Content = _ViewModifier_Content<Self>

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs
    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs
}

extension ViewModifier where Self.Body == Never {
    public func body(content: Self.Content) -> Self.Body {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

extension ViewModifier {
    var _content: Self.Body {
        body(content: _ViewModifier_Content())
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        if let modifierType = self as? any _ViewInputsModifier.Type {
            func makeInputs<T: _ViewInputsModifier>(_: T.Type, graph: _GraphValue<Any>, inputs: inout _ViewInputs) {
                T._makeViewInputs(modifier: graph.unsafeCast(to: T.self), inputs: &inputs)
            }
            var inputs = inputs
            makeInputs(modifierType, graph: modifier.unsafeCast(to: Any.self), inputs: &inputs)
            return body(_Graph(), inputs)
        }
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var value = _ViewModifierBodyContext.body
        value[ObjectIdentifier(Content.self)] = _ViewModifierBodyContext._Body(makeView: body, makeViewList: nil)
        return _ViewModifierBodyContext.$body.withValue(value) {
            Body._makeView(view: modifier[\._content], inputs: inputs)
        }
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        if let modifierType = self as? any _ViewInputsModifier.Type {
            func makeInputs<T: _ViewInputsModifier>(_: T.Type, graph: _GraphValue<Any>, inputs: inout _ViewListInputs) {
                T._makeViewListInputs(modifier: graph.unsafeCast(to: T.self), inputs: &inputs)
            }
            var inputs = inputs
            makeInputs(modifierType, graph: modifier.unsafeCast(to: Any.self), inputs: &inputs)
            return body(_Graph(), inputs)
        }
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var value = _ViewModifierBodyContext.body
        value[ObjectIdentifier(Content.self)] = _ViewModifierBodyContext._Body(makeView: nil, makeViewList: body)
        return _ViewModifierBodyContext.$body.withValue(value) {
            Body._makeViewList(view: modifier[\._content], inputs: inputs)
        }
    }
}

// _GraphInputsModifier is a type of modifier that modifies _GraphInputs.
public protocol _GraphInputsModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs)
}

// _ViewInputsModifier is a type of modifier that modifies _ViewInputs.
protocol _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs)
    static func _makeViewListInputs(modifier: _GraphValue<Self>, inputs: inout _ViewListInputs)
}

extension _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        fatalError()
    }
    static func _makeViewListInputs(modifier: _GraphValue<Self>, inputs: inout _ViewListInputs) {
        fatalError("Implement with AG")
    }
}

// _UnaryViewModifier is for View-Modifiers with Body = Never without _makeViewList.
protocol _UnaryViewModifier {
}

extension ViewModifier where Self: _GraphInputsModifier, Self.Body == Never {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        Self._makeInputs(modifier: modifier, inputs: &inputs.base)
        return body(_Graph(), inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        Self._makeInputs(modifier: modifier, inputs: &inputs.base)
        return body(_Graph(), inputs)
    }
}

extension ViewModifier where Self: Animatable {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

extension ViewModifier {
    @inlinable public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
          return .init(content: self, modifier: modifier)
      }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public var body: Never {
        fatalError("body() should not be called on \(Self.self).")
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        Modifier._makeView(modifier: modifier[\.modifier], inputs: inputs) { _, inputs in
            Content._makeView(modifier: modifier[\.content], inputs: inputs, body: body)
        }
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        Modifier._makeViewList(modifier: modifier[\.modifier], inputs: inputs) { _, inputs in
            Content._makeViewList(modifier: modifier[\.content], inputs: inputs, body: body)
        }
    }
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        return ModifiedContent(content: self, modifier: modifier)
    }
}

