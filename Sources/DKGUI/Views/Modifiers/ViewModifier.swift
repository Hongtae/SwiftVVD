//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

public struct _ViewModifier_Content<Modifier> where Modifier: ViewModifier {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if let body = inputs._modifierBody[ObjectIdentifier(Modifier.self)] {
            return body(_Graph(), inputs)
        }
        return _ViewOutputs(view: _ViewGenerator(graph: view), preferences: .init(preferences: []))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if let body = inputs._modifierBody[ObjectIdentifier(Modifier.self)] {
            return body(_Graph(), inputs)
        }
        return _ViewListOutputs(viewList: .staticList([_ViewGenerator(graph: view)]), preferences: .init(preferences: []))
    }
}

extension _ViewModifier_Content: View {
    public var body: Never { neverBody() }

    struct _ViewGenerator : ViewGenerator {
        let graph: _GraphValue<_ViewModifier_Content>
        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            nil
        }
    }
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
    var _body: Body { self.body(content: .init()) }
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        inputs._modifierBody[ObjectIdentifier(self)] = body
        return Self.Body._makeView(view: modifier[\._body], inputs: inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        inputs._modifierBody[ObjectIdentifier(self)] = body
        return Self.Body._makeViewList(view: modifier[\._body], inputs: inputs)
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
    static func _makeView(modifier: _GraphValue<Self>, content: any ViewGenerator, inputs: _GraphInputs) -> any ViewGenerator
    static func _makeViewList(modifier: _GraphValue<Self>, content: any ViewListGenerator, inputs: _GraphInputs) -> any ViewListGenerator
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

        let viewOutputs = body(_Graph(), inputs)
        if let layoutModifier = self as? any _ViewLayoutModifier.Type {
            func _makeView<T: _ViewLayoutModifier>(_: T.Type, modifier: Any, content: any ViewGenerator, inputs: _GraphInputs) -> any ViewGenerator {
                T._makeView(modifier: modifier as! _GraphValue<T>, content: content, inputs: inputs)
            }
            let generator = _makeView(layoutModifier, modifier: modifier, content: viewOutputs.view, inputs: inputs.base)
            return _ViewOutputs(view: generator, preferences: .init(preferences: []))
        }
        return viewOutputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)

        let viewListOutputs = body(_Graph(), inputs)
        if let layoutModifier = self as? any _ViewLayoutModifier.Type {
            func _makeViewList<T: _ViewLayoutModifier>(_: T.Type, modifier: Any, content: any ViewListGenerator, inputs: _GraphInputs) -> any ViewListGenerator {
                T._makeViewList(modifier: modifier as! _GraphValue<T>, content: content, inputs: inputs)
            }
            let generators = _makeViewList(layoutModifier, modifier: modifier, content: viewListOutputs.viewList, inputs: inputs.base)
            return _ViewListOutputs(viewList: generators, preferences: .init(preferences: []))
        }
        return viewListOutputs
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
        Modifier._makeView(modifier: view[\.modifier], inputs: inputs) { _, inputs in
            Content._makeView(view: view[\.content], inputs: inputs)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if Modifier.self is _UnaryViewModifier.Type {
            let inputs = _ViewInputs(base: inputs.base, preferences: inputs.preferences)
            let outputs = Modifier._makeView(modifier: view[\.modifier], inputs: inputs) { _, inputs in
                Content._makeView(view: view[\.content], inputs: inputs)
            }
            return _ViewListOutputs(viewList: .staticList([outputs.view]), preferences: .init(preferences: []))
        }
        return Modifier._makeViewList(modifier: view[\.modifier], inputs: inputs) { _, inputs in
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

class ViewModifierContext<Modifier> : ViewContext {
    let content: ViewContext
    let modifier: Modifier

    init(content: ViewContext, modifier: Modifier, inputs: _GraphInputs, graph: _GraphValue<Modifier>) {
        self.content = content
        self.modifier = modifier
        super.init(inputs: inputs, graph: graph)

        self._debugDraw = true
        self._debugDrawShading = .color(.red.opacity(0.4))
    }

    override func resolveGraphInputs<T>(encloser: T, graph: _GraphValue<T>) {
        super.resolveGraphInputs(encloser: encloser, graph: graph)
        self.content.resolveGraphInputs(encloser: encloser, graph: graph)
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        self.content.updateEnvironment(environmentValues)
    }

    override func loadResources(_ context: GraphicsContext) {
        super.loadResources(context)
        self.content.loadResources(context)
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        let width = self.content.frame.width
        let height = self.content.frame.height
        guard width > 0 && height > 0 else {
            return
        }

        if frame.intersection(self.content.frame).isNull {
            return
        }
        let frame = self.content.frame
        self.content.drawView(frame: frame, context: context)
    }

    override func setLayoutProperties(_ properties: LayoutProperties) {
        super.setLayoutProperties(properties)
        self.content.setLayoutProperties(properties)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        self.content.sizeThatFits(proposal)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let proposal = ProposedViewSize(width: frame.width,
                                        height: frame.height)
        self.content.place(at: center, anchor: .center, proposal: proposal)
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.frame.contains(location) {
            let frame = self.content.frame
            if frame.contains(location) {
                let loc = location - frame.origin
                if self.content.handleMouseWheel(at: loc, delta: delta) {
                    return true
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }

    override func update(transform t: AffineTransform) {
        super.update(transform: t)
        self.content.update(transform: t)
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        super.update(tick: tick, delta: delta, date: date)
        self.content.update(tick: tick, delta: delta, date: date)
    }
}
