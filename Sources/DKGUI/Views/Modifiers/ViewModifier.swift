//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct _ViewModifier_Content<Modifier> where Modifier: ViewModifier {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if let makeView = view.value.makeView {
            return makeView(_Graph(), inputs)
        }
        fatalError()
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if let makeViewList = view.value.makeViewList {
            return makeViewList(_Graph(), inputs)
        }
        fatalError()
    }
    var makeView: ((_Graph, _ViewInputs)->_ViewOutputs)?
    var makeViewList: ((_Graph, _ViewListInputs)->_ViewListOutputs)?
}

extension _ViewModifier_Content: View {
    public var body: Never { neverBody() }
}

public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder func body(content: Self.Content) -> Self.Body
    typealias Content = _ViewModifier_Content<Self>

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs
    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs
}

extension ViewModifier where Self.Body == Never {
    public func body(content: Self.Content) -> Self.Body { neverBody() }
}

extension ViewModifier {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        inputs.modifiers.append(modifier.value)
        let makeView: _ViewOutputs.MakeView = {
            let body = modifier.value.body(content: Content(makeView: body))
            let outputs = Self.Body._makeView(view: _GraphValue(body), inputs: inputs)
            return outputs.makeView()
        }
        return _ViewOutputs(makeView: makeView)
    }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        inputs.inputs.modifiers.append(modifier.value)
        let body = modifier.value.body(content: Content(makeViewList: body))
        let outputs = Self.Body._makeViewList(view: _GraphValue(body), inputs: inputs)
        return _ViewListOutputs(item: .viewList([outputs]))
    }
}

extension ViewModifier where Self: _GraphInputsModifier, Self.Body == Never {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        var graphInputs = _GraphInputs(environmentValues: inputs.environmentValues)
        Self._makeInputs(modifier: modifier, inputs: &graphInputs)
        inputs.environmentValues = graphInputs.environmentValues

        let makeView: _ViewOutputs.MakeView = {
            let outputs = body(_Graph(), inputs)
            return outputs.makeView()
        }
        return _ViewOutputs(makeView: makeView)
    }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        var graphInputs = _GraphInputs(environmentValues: inputs.inputs.environmentValues)
        Self._makeInputs(modifier: modifier, inputs: &graphInputs)
        inputs.inputs.environmentValues = graphInputs.environmentValues

        let outputs = body(_Graph(), inputs)
        return _ViewListOutputs(item: .viewList([outputs]))
    }
}

extension ViewModifier where Self: Animatable {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError()
    }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        fatalError()
    }
}

extension ViewModifier {
    @inlinable public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
          return .init(content: self, modifier: modifier)
      }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public var body: Never { neverBody() }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Modifier._makeView(modifier: view[\.modifier], inputs: inputs) {
            graph, inputs in
            Content._makeView(view: view[\.content], inputs: inputs)
        }
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Modifier._makeViewList(modifier: view[\.modifier], inputs: inputs) {
            graph, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
    }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        Modifier._makeView(modifier: modifier[\.modifier], inputs: inputs) {
            graph, inputs in
            Content._makeView(modifier: modifier[\.content], inputs: inputs, body: body)
        }
    }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        Modifier._makeViewList(modifier: modifier[\.modifier], inputs: inputs) {
            graph, inputs in
            Content._makeViewList(modifier: modifier[\.content], inputs: inputs, body: body)
        }
    }
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        return ModifiedContent(content: self, modifier: modifier)
    }
}
