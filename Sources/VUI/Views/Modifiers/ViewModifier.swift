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
        if let body = _ViewModifierBodyContext.body[ObjectIdentifier(self)]?.makeView {
            return body(_Graph(), inputs)
        }
        fatalError("Unable to get view body of \(Modifier.self)")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if let body = _ViewModifierBodyContext.body[ObjectIdentifier(self)]?.makeViewList {
            return body(_Graph(), inputs)
        }
        if let body = _ViewModifierBodyContext.body[ObjectIdentifier(self)]?.makeView {
            let outputs = body(_Graph(), inputs.inputs)
            return _ViewListOutputs(views: .staticList(outputs.view))
        }
        fatalError("Unable to get view body of \(Modifier.self)")
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
        var _inputs = inputs.inputs
        Self._makeViewInputs(modifier: modifier, inputs: &_inputs)
        inputs = _inputs.listInputs
    }
}

// _UnaryViewModifier is for View-Modifiers with Body = Never without _makeViewList.
protocol _UnaryViewModifier {
}

protocol _ViewLayoutModifier {
    static func _makeLayoutView(modifier: _GraphValue<Self>, inputs: _ViewInputs, content: any ViewGenerator) -> any ViewGenerator
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
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)

        let outputs = body(_Graph(), inputs)
        if let view = outputs.view, let layoutModifier = self as? any _ViewLayoutModifier.Type {
            func _makeView<T: _ViewLayoutModifier, U>(_: T.Type, modifier: _GraphValue<U>, view: any ViewGenerator) -> any ViewGenerator {
                T._makeLayoutView(modifier: modifier.unsafeCast(to: T.self), inputs: inputs, content: view)
            }
            return _ViewOutputs(view: _makeView(layoutModifier, modifier: modifier, view: view))
        }
        return outputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)

        let outputs = body(_Graph(), inputs)
        if let layoutModifier = self as? any _ViewLayoutModifier.Type {
            let inputs = inputs.inputs
            func _makeView<T: _ViewLayoutModifier, U>(_: T.Type, modifier: _GraphValue<U>, view: any ViewGenerator) -> any ViewGenerator {
                T._makeLayoutView(modifier: modifier.unsafeCast(to: T.self), inputs: inputs, content: view)
            }
            if var staticList = outputs.views as? StaticViewList & ViewListGenerator {
                let views = staticList.views.map { wrapped in
                    _makeView(layoutModifier, modifier: modifier, view: wrapped)
                }
                staticList.views = views
                return _ViewListOutputs(views: staticList)
            } else {
                let views = outputs.views.wrapper(inputs: inputs.base) { _, baseInputs, view in
                    _makeView(layoutModifier, modifier: modifier, view: view)
                }
                return _ViewListOutputs(views: views)
            }
        }
        return outputs
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
    
    private static func isProhibitedByStyleContext<S: StyleContext>(_: S.Type) -> Bool {
        S._isModifierAllowed(Modifier.self) == false
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if let styleProxy = inputs.base.styleContext, isProhibitedByStyleContext(styleProxy.type) {
            return Content._makeView(view: view[\.content], inputs: inputs)
        }
        
        if Modifier.self is _UnaryViewModifier.Type {
            let outputs = Content._makeView(view: view[\.content], inputs: inputs)
            if let multiView = outputs.view as? any MultiViewGenerator {
                if var staticMultiView = multiView as? any StaticViewList & ViewGenerator {
                    let views = staticMultiView.views.map { wrapped in
                        let outputs = Modifier._makeView(modifier: view[\.modifier],
                                                         inputs: inputs) { _, inputs in
                            var view = wrapped
                            view.mergeInputs(inputs.base)
                            return _ViewOutputs(view: view)
                        }
                        return outputs.view ?? wrapped
                    }
                    staticMultiView.views = views
                    return _ViewOutputs(view: staticMultiView)
                } else {
                    let view = DynamicMultiViewGenerator(graph: view,
                                                         baseInputs: inputs.base,
                                                         body: multiView)
                    return _ViewOutputs(view: view)
                }
            }
            return Modifier._makeView(modifier: view[\.modifier], inputs: inputs) { _, inputs in
                var view = outputs.view
                view?.mergeInputs(inputs.base)
                return _ViewOutputs(view: view)
            }
        }
        return Modifier._makeView(modifier: view[\.modifier], inputs: inputs) { _, inputs in
            let outputs = Content._makeView(view: view[\.content], inputs: inputs)
            return outputs
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        assert(view.isRoot == false)
        
        if let styleProxy = inputs.base.styleContext, isProhibitedByStyleContext(styleProxy.type) {
            return Content._makeViewList(view: view[\.content], inputs: inputs)
        }

        let modifier = view[\.modifier]
        if Modifier.self is _UnaryViewModifier.Type {
            let outputs = Content._makeViewList(view: view[\.content], inputs: inputs)
            let inputs = inputs.inputs
            if let staticList = outputs.views as? StaticViewList & ViewListGenerator {
                let views = staticList.views.map { content in
                    Modifier._makeView(modifier: modifier, inputs: inputs) { _, inputs in
                        var content = content
                        content.mergeInputs(inputs.base)
                        return _ViewOutputs(view: content)
                    }
                }
                return _ViewListOutputs(views: .staticList(views.compactMap { $0.view }))
            } else {
                let views = outputs.views.wrapper(inputs: inputs.base) { _, _, view in
                    let outputs = Modifier._makeView(modifier: modifier,
                                                     inputs: inputs) { _, inputs in
                        var view = view
                        view.mergeInputs(inputs.base)
                        return _ViewOutputs(view: view)
                    }
                    return outputs.view ?? view
                }
                return _ViewListOutputs(views: views)
            }
        }
        return Modifier._makeViewList(modifier: modifier, inputs: inputs) { _, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
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

class ViewModifierContext<Modifier>: GenericViewContext<Modifier> where Modifier: ViewModifier {
    var modifier: Modifier? { self.view }
}
