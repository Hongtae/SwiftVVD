//
//  File: LabelStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol LabelStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = LabelStyleConfiguration
}

public struct LabelStyleConfiguration {
    public struct Title {
        public typealias Body = Never
    }
    public struct Icon {
        public typealias Body = Never
    }
    public var title: LabelStyleConfiguration.Title { .init() }
    public var icon: LabelStyleConfiguration.Icon { .init() }
}

extension LabelStyleConfiguration.Title: View {}
extension LabelStyleConfiguration.Icon: View {}
extension LabelStyleConfiguration.Title: _PrimitiveView {}
extension LabelStyleConfiguration.Icon: _PrimitiveView {}


extension LabelStyleConfiguration.Title {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if let proxy = inputs.base.customInputs.value(forKey: _StaticSourceInputKey<Self>.self) {
            return proxy.makeView(_Graph(), inputs: inputs)
        }
        return _ViewOutputs()
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }
}

extension LabelStyleConfiguration.Icon {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if let proxy = inputs.base.customInputs.value(forKey: _StaticSourceInputKey<Self>.self) {
            return proxy.makeView(_Graph(), inputs: inputs)
        }
        return _ViewOutputs()
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }
}

public struct DefaultLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

public struct IconOnlyLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
    }
}

public struct TitleAndIconLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

public struct TitleOnlyLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.title
    }
}

struct _MenuItemLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.clear)
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
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

struct LabelStyleWritingModifier<Style>: ViewModifier where Style: LabelStyle {
    let style: Style
    typealias Body = Never
}

extension LabelStyleWritingModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let styleAttr: Attribute<LabelStyleModifier<Style>> = graph.makeInput(
            value: LabelStyleModifier(style: modifier._attribute.value.style))
        let anyMod = AnyStyleModifier(
            value: styleAttr.identifier,
            _type: StyleModifierType<LabelStyleModifier<Style>>.self)
        var inputs = inputs
        let stack = inputs.base.customInputs.value(forKey: StyleInput<LabelStyleConfiguration>.self)
        inputs.base.customInputs.setValue(stack.pushing(anyMod), forKey: StyleInput<LabelStyleConfiguration>.self)
        return body(_Graph(), inputs)
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }
        let styleAttr: Attribute<LabelStyleModifier<Style>> = graph.makeInput(
            value: LabelStyleModifier(style: modifier._attribute.value.style))
        let anyMod = AnyStyleModifier(
            value: styleAttr.identifier,
            _type: StyleModifierType<LabelStyleModifier<Style>>.self)
        var inputs = inputs
        let stack = inputs.base.customInputs.value(forKey: StyleInput<LabelStyleConfiguration>.self)
        inputs.base.customInputs.setValue(stack.pushing(anyMod), forKey: StyleInput<LabelStyleConfiguration>.self)
        return body(_Graph(), inputs)
    }
}

extension View {
    public func labelStyle<S>(_ style: S) -> some View where S: LabelStyle {
        modifier(LabelStyleWritingModifier(style: style))
    }
}
