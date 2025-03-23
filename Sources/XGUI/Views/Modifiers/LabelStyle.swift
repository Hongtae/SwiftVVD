//
//  File: LabelStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public protocol LabelStyle {
    associatedtype Body : View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = LabelStyleConfiguration
}

public struct LabelStyleConfiguration {
    public struct Title {
        public typealias Body = Never
        let view: ViewProxy?
    }
    public struct Icon {
        public typealias Body = Never
        let view: ViewProxy?
    }
    public var title: LabelStyleConfiguration.Title {
        .init(view: _title)
    }
    public var icon: LabelStyleConfiguration.Icon {
        .init(view: _icon)
    }

    let _title: ViewProxy?
    let _icon: ViewProxy?
    init(_ title: ViewProxy?, _ icon: ViewProxy?) {
        self._title = title
        self._icon = icon
    }
}

extension LabelStyleConfiguration.Title : View {}
extension LabelStyleConfiguration.Icon : View {}
extension LabelStyleConfiguration.Title : _PrimitiveView {}
extension LabelStyleConfiguration.Icon : _PrimitiveView {}

extension LabelStyleConfiguration.Title {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(baseInputs: inputs.base) { inputs in
            LabelStyleConfigurationTitleViewContext(graph: view, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = UnaryViewGenerator(baseInputs: inputs.base) { inputs in
            LabelStyleConfigurationTitleViewContext(graph: view, inputs: inputs)
        }
        return _ViewListOutputs(views: .staticList(view))
    }
}

extension LabelStyleConfiguration.Icon {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(baseInputs: inputs.base) { inputs in
            LabelStyleConfigurationIconViewContext(graph: view, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = UnaryViewGenerator(baseInputs: inputs.base) { inputs in
            LabelStyleConfigurationIconViewContext(graph: view, inputs: inputs)
        }
        return _ViewListOutputs(views: .staticList(view))
    }
}

public struct DefaultLabelStyle : LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

public struct IconOnlyLabelStyle : LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
    }
}

public struct TitleAndIconLabelStyle : LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

public struct TitleOnlyLabelStyle : LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.title
    }
}

extension LabelStyle where Self == DefaultLabelStyle {
    public static var automatic: DefaultLabelStyle { .init() }
}

extension LabelStyle where Self == IconOnlyLabelStyle {
  public static var iconOnly: IconOnlyLabelStyle { .init() }
}

extension LabelStyle where Self == TitleAndIconLabelStyle {
    public static var titleAndIcon: TitleAndIconLabelStyle { .init() }
}

extension LabelStyle where Self == TitleOnlyLabelStyle {
    public static var titleOnly: TitleOnlyLabelStyle { .init() }
}

struct LabelStyleWritingModifier<Style> : ViewModifier where Style : LabelStyle {
    let style: Style
    typealias Body = Never
}

extension LabelStyleWritingModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        inputs.layouts.labelStyles.append(LabelStyleProxy(modifier[\.style]))
        return body(_Graph(), inputs)
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        inputs.layouts.labelStyles.append(LabelStyleProxy(modifier[\.style]))
        return body(_Graph(), inputs)
    }
}

extension View {
    public func labelStyle<S>(_ style: S) -> some View where S : LabelStyle {
        modifier(LabelStyleWritingModifier(style: style))
    }
}

struct LabelStyleProxy {
    let type: any LabelStyle.Type
    let graph: _GraphValue<Any>
    init<S: LabelStyle>(_ graph: _GraphValue<S>) {
        self.type = S.self
        self.graph = graph.unsafeCast(to: Any.self)
    }
    func resolve(_ view: ViewContext) -> (any LabelStyle)? {
        view.value(atPath: graph) as? (any LabelStyle)
    }
}

private class LabelStyleConfigurationTitleViewContext : DynamicViewContext<LabelStyleConfiguration.Title> {
    override func updateContent() {
        self.view = nil
        self.view = value(atPath: self.graph)
        if let view, let proxy = view.view {
            let outputs = proxy.makeView(_Graph(), inputs: _ViewInputs(base: self.inputs))
            self.body = outputs.view?.makeView()
            self.body?.updateContent()
        } else {
            self.invalidate()
            fatalError("Unable to recover view for \(graph)")
        }
    }
}

private class LabelStyleConfigurationIconViewContext : DynamicViewContext<LabelStyleConfiguration.Icon> {
    override func updateContent() {
        self.view = nil
        self.view = value(atPath: self.graph)
        if let view, let proxy = view.view {
            let outputs = proxy.makeView(_Graph(), inputs: _ViewInputs(base: self.inputs))
            self.body = outputs.view?.makeView()
            self.body?.updateContent()
        } else {
            self.invalidate()
            fatalError("Unable to recover view for \(graph)")
        }
    }
}
