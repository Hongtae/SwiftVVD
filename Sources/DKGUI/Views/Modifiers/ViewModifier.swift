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
        if let makeViewList = view.value.makeViewList {
            let listInputs = _ViewListInputs(inputs: inputs)
            let listOutputs = makeViewList(_Graph(), listInputs)

            let subviews = listOutputs.viewProxies
            if subviews.count == 1 {
                return _ViewOutputs(item: .view(subviews[0]))
            }
            let viewProxy = ViewGroupProxy(view: view.value, inputs: inputs, subviews: subviews, layout: VStackLayout())
            return _ViewOutputs(item: .view(viewProxy))
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
    public func body(content: Self.Content) -> Self.Body {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

extension ViewModifier {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        inputs.modifiers.append(modifier.value)
        let body = modifier.value.body(content: Content(makeView: body))
        return Self.Body._makeView(view: _GraphValue(body), inputs: inputs)
    }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        inputs.inputs.modifiers.append(modifier.value)
        let body = modifier.value.body(content: Content(makeViewList: body))
        let outputs = Self.Body._makeViewList(view: _GraphValue(body), inputs: inputs)
        return _ViewListOutputs(item: .viewList([outputs]))
    }
}

// _GraphInputsModifier is a type of modifier that modifies _GraphInputs.
public protocol _GraphInputsModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs)
}

// _ViewInputsModifier is a type of modifier that modifies _ViewInputs.
public protocol _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs)
}

// _UnaryViewModifier is for View-Modifiers with Body = Never without _makeViewList.
protocol _UnaryViewModifier {
}

protocol _ViewLayoutModifier: _UnaryViewModifier {
    func makeLayoutViewProxy(content view: ViewProxy, inputs: _ViewInputs) -> ViewProxy
}

extension ViewModifier where Self: _GraphInputsModifier, Self.Body == Never {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        var graphInputs = _GraphInputs(environmentValues: inputs.environmentValues)
        Self._makeInputs(modifier: modifier, inputs: &graphInputs)
        inputs.environmentValues = graphInputs.environmentValues
        return body(_Graph(), inputs)
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

extension ViewModifier where Self: _ViewInputsModifier, Self.Body == Never {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        Self._makeViewInputs(modifier: modifier, inputs: &inputs)
        return body(_Graph(), inputs)
    }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        Self._makeViewInputs(modifier: modifier, inputs: &inputs.inputs)

        let outputs = body(_Graph(), inputs)
        return _ViewListOutputs(item: .viewList([outputs]))
    }
}

extension ViewModifier where Self: Animatable {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {

        var modifier = modifier
        let graphInputs = _GraphInputs(environmentValues: inputs.environmentValues)
        Self._makeAnimatable(value: &modifier, inputs: graphInputs)

        let viewOutputs = body(_Graph(), inputs)
        if let layoutModifier = modifier.value as? _ViewLayoutModifier {
            let viewProxy = layoutModifier.makeLayoutViewProxy(content: viewOutputs.view, inputs: inputs)
            return _ViewOutputs(item: .view(viewProxy))
        }
        return viewOutputs
    }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {

        var modifier = modifier
        let graphInputs = _GraphInputs(environmentValues: inputs.inputs.environmentValues)
        Self._makeAnimatable(value: &modifier, inputs: graphInputs)

        let outputs = body(_Graph(), inputs)
        return _ViewListOutputs(item: .viewList([outputs]))
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
        Modifier._makeView(modifier: view[\.modifier], inputs: inputs) {
            graph, inputs in
            let content = inputs.environmentValues._resolve(view[\.content])
            return Content._makeView(view: content, inputs: inputs)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let modifier = view[\.modifier]
        if modifier.value is _UnaryViewModifier {
            return _ViewListOutputs(item: .view(.init(view: AnyView(view.value), inputs: inputs.inputs)))
        }
        return Modifier._makeViewList(modifier: modifier, inputs: inputs) {
            graph, inputs in
            let content = view[\.content]
            if content.value is _ViewProxyProvider {
                let inputs: _ViewInputs = inputs.inputs
                return _ViewListOutputs(item: .view(.init(view: AnyView(content.value), inputs: inputs)))
            }
            let view = inputs.inputs.environmentValues._resolve(content)
            return Content._makeViewList(view: view, inputs: inputs)
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
