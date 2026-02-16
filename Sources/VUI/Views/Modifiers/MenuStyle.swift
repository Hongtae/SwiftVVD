//
//  File: MenuStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public protocol MenuStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = MenuStyleConfiguration
}

public struct MenuStyleConfiguration {
    public struct Label: View {
        public typealias Body = Never
        let view: ViewProxy?
    }

    public struct Content: View {
        public typealias Body = Never
        let view: ViewProxy?
    }

    public var label: MenuStyleConfiguration.Label { .init(view: _label) }
    public var content: MenuStyleConfiguration.Content { .init(view: _content) }

    let _label: ViewProxy?
    let _content: ViewProxy?
    init(_ label: ViewProxy?, _ content: ViewProxy?) {
        self._label = label
        self._content = content
    }
}

extension MenuStyleConfiguration.Label: _PrimitiveView {}
extension MenuStyleConfiguration.Content: _PrimitiveView {}

extension MenuStyleConfiguration.Label {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            MenuStyleConfigurationLabelViewContext(graph: graph, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            MenuStyleConfigurationLabelViewContext(graph: graph, inputs: inputs)
        }
        return _ViewListOutputs(views: .staticList(view))
    }
}

extension MenuStyleConfiguration.Content {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            MenuStyleConfigurationContentViewContext(graph: graph, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            MenuStyleConfigurationContentViewContext(graph: graph, inputs: inputs)
        }
        return _ViewListOutputs(views: .staticList(view))
    }
}

public struct DefaultMenuStyle: MenuStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(MenuDropdownModifier(content: configuration.content))
    }
}

extension MenuStyle where Self == DefaultMenuStyle {
    public static var automatic: DefaultMenuStyle { .init() }
}

struct MenuStyleProxy {
    let type: any MenuStyle.Type
    let graph: _GraphValue<Any>
    init<S: MenuStyle>(_ graph: _GraphValue<S>) {
        self.type = S.self
        self.graph = graph.unsafeCast(to: Any.self)
    }
    func resolve(_ resolver: some _GraphValueResolver) -> (any MenuStyle)? {
        resolver.value(atPath: graph) as? (any MenuStyle)
    }
}

struct MenuStyleModifier<Style>: ViewModifier where Style: MenuStyle {
    let style: Style
    typealias Body = Never
}

extension MenuStyleModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        inputs.layouts.menuStyles.append(MenuStyleProxy(modifier[\.style]))
        return body(_Graph(), inputs)
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        inputs.layouts.menuStyles.append(MenuStyleProxy(modifier[\.style]))
        return body(_Graph(), inputs)
    }
}

extension View {
    public func menuStyle<S>(_ style: S) -> some View where S: MenuStyle {
        modifier(MenuStyleModifier(style: style))
    }
}

// MARK: - DynamicViewContext for Label/Content

private class MenuStyleConfigurationLabelViewContext: DynamicViewContext<MenuStyleConfiguration.Label> {
    override func updateContent() {
        let oldProxy = self.view?.view
        self.view = nil
        if var view = value(atPath: self.graph) {
            self.resolveGraphInputs()
            self.updateView(&view)
            self.requiresContentUpdates = false
            self.view = view
        }
        if let view, let proxy = view.view {
            if self.body == nil || proxy != oldProxy {
                let outputs = proxy.makeView(_Graph(), inputs: _ViewInputs(base: self.inputs))
                self.body = outputs.view?.makeView()
            }
            self.body?.updateContent()
        } else {
            self.invalidate()
            fatalError("Unable to recover view for \(graph)")
        }
        self.sharedContext.needsLayout = true
    }
}

private class MenuStyleConfigurationContentViewContext: DynamicViewContext<MenuStyleConfiguration.Content> {
    override func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let result = super.value(atPath: graph) { return result }
        return self.sharedContext.auxiliarySceneContext?.hostContext?.root?.value(atPath: graph)
    }

    override func updateContent() {
        let oldProxy = self.view?.view
        self.view = nil
        if var view = value(atPath: self.graph) {
            self.resolveGraphInputs()
            self.updateView(&view)
            self.requiresContentUpdates = false
            self.view = view
        }
        if let view, let proxy = view.view {
            if self.body == nil || proxy != oldProxy {
                let outputs = proxy.makeView(_Graph(), inputs: _ViewInputs(base: self.inputs))
                self.body = outputs.view?.makeView()
            }
            self.body?.updateContent()
        } else {
            self.invalidate()
            fatalError("Unable to recover view for \(graph)")
        }
        self.sharedContext.needsLayout = true
    }
}
