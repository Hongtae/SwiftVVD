//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

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
        return _ViewListOutputs(viewList: [_ViewGenerator(graph: view)], preferences: .init(preferences: []))
    }
}

extension _ViewModifier_Content: View {
    public var body: Never { neverBody() }

    struct _ViewGenerator : ViewGenerator {
        let graph: _GraphValue<_ViewModifier_Content>
        func makeView(content: _ViewModifier_Content) -> ViewContext? {
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
    func _makeView(superview: some View, modifier: _GraphValue<Self>, inputs: _GraphInputs) -> any ViewGenerator
}

extension ViewModifier where Self: _GraphInputsModifier, Self.Body == Never {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        Self._makeInputs(modifier: modifier, inputs: &inputs.base)

        //return body(_Graph(), inputs)
        fatalError()
    }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        Self._makeInputs(modifier: modifier, inputs: &inputs.base)

        //return body(_Graph(), inputs)
        fatalError()
    }
}

extension ViewModifier where Self: Animatable {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)

        if let layoutModifier = self as? any _ViewLayoutModifier.Type {
            // make layout view
        }
        let viewOutputs = body(_Graph(), inputs)
        return viewOutputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)

        if let layoutModifier = self as? any _ViewLayoutModifier.Type {
            // make layout view
        }
        let viewOutputs = body(_Graph(), inputs)
        return viewOutputs
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
        let outputs = Modifier._makeView(modifier: view[\.modifier], inputs: inputs) { _, inputs in
            Content._makeView(view: view[\.content], inputs: inputs)
        }
        if let modifier = outputs.view as? any ViewModifierViewGenerator {
            let generator = ModifiedContentViewGenerator(graph: view,
                                                         modifier: modifier,
                                                         baseInputs: inputs.base,
                                                         preferences: inputs.preferences)
            return _ViewOutputs(view: generator, preferences: .init(preferences: []))
        } else {
            return outputs
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let outputs = Modifier._makeViewList(modifier: view[\.modifier], inputs: inputs) { _, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
        let viewList: [any ViewGenerator] = outputs.viewList.map {
            if let modifier = $0 as? any ViewModifierViewGenerator {
                return ModifiedContentViewGenerator(graph: view,
                                                    modifier: modifier,
                                                    baseInputs: inputs.base,
                                                    preferences: inputs.preferences)

            } else {
                return $0
            }
        }
        return _ViewListOutputs(viewList: viewList, preferences: .init(preferences: []))
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

class ViewModifierContext<Modifier> : ViewContext where Modifier : ViewModifier {
    let content: ViewContext
    let modifier: Modifier

    init(content: ViewContext, modifier: Modifier, inputs: _GraphInputs, graph: _GraphValue<Modifier>) {
        self.content = content
        self.modifier = modifier
        super.init(inputs: inputs, graph: graph)
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
        var context = context
        context.environment = self.content.environmentValues
        let frame = self.content.frame.standardized
        self.content.drawView(frame: frame, context: context)
    }

    override func setLayoutProperties(_ properties: LayoutProperties) {
        super.setLayoutProperties(properties)
        self.content.setLayoutProperties(properties)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let size = super.sizeThatFits(proposal)
        let s = self.content.sizeThatFits(proposal)
        return CGSize(width: max(size.width, s.width),
                      height: max(size.height, s.height))
    }

    override func layoutSubviews() {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let proposal = ProposedViewSize(width: frame.width,
                                        height: frame.height)
        self.content.place(at: center, anchor: .center, proposal: proposal)
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.frame.standardized.contains(location) {
            let frame = self.content.frame.standardized
            if frame.contains(location) {
                let loc = location - frame.origin
                if self.content.handleMouseWheel(at: loc, delta: delta) {
                    return true
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }
}

protocol ViewModifierViewGenerator : ViewGenerator where Content : ViewModifier {
    var content: any ViewGenerator { get }
    func makeView(modifier: Content, content: ViewContext?) -> ViewContext?
}

extension ViewModifierViewGenerator {
    func makeView(content: any ViewModifier) -> ViewContext? {
        nil
    }
}

class ModifiedContentViewContext<Content> : ViewContext where Content : View {
    let content: ViewContext
    let modifier: ViewContext

    init(view: Content, content: ViewContext, modifier: ViewContext, inputs: _GraphInputs, graph: _GraphValue<Content>) {
        self.content = content
        self.modifier = modifier
        super.init(inputs: inputs, graph: graph)
    }
}

struct ModifiedContentViewGenerator<Content> : ViewGenerator where Content : View {
    let graph: _GraphValue<Content>
    let modifier: any ViewModifierViewGenerator
    var baseInputs: _GraphInputs
    var preferences: PreferenceInputs
    var traits: ViewTraitKeys = ViewTraitKeys()

    func makeView(content view: Content) -> ViewContext? {
        func makeViewContext<T: ViewGenerator>(_ gen: T) -> ViewContext? {
            if let view = self.graph.value(atPath: gen.graph, from: view) {
                return gen.makeView(content: view)
            }
            return nil
        }
        let content = self.modifier.content
        if let content = makeViewContext(content) {
            func makeModifier<T: ViewModifierViewGenerator>(_ gen: T) -> ViewContext? {
                if let mod = self.graph.value(atPath: gen.graph, from: view) {
                    return gen.makeView(modifier: mod, content: content)
                }
                return nil
            }
            if let modifier = makeModifier(modifier) {
                return ModifiedContentViewContext(view: view,
                                                  content: content,
                                                  modifier: modifier,
                                                  inputs: baseInputs,
                                                  graph: graph)
            }
            return content
        }
        return nil
    }
}
