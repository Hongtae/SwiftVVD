//
//  File: LabelStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol LabelStyle {
    associatedtype Body : View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = LabelStyleConfiguration
}

public struct LabelStyleConfiguration {
    public struct Title {
        public typealias Body = Never
        let view: AnyView
    }
    public struct Icon {
        public typealias Body = Never
        let view: AnyView
    }
    public var title: LabelStyleConfiguration.Title {
        .init(view: _title)
    }
    public var icon: LabelStyleConfiguration.Icon {
        .init(view: _icon)
    }

    let _title: AnyView
    let _icon: AnyView
    init(_ title: some View, _ icon: some View) {
        self._title = AnyView(title)
        self._icon = AnyView(icon)
    }
}

extension LabelStyleConfiguration.Title : View {}
extension LabelStyleConfiguration.Icon : View {}
extension LabelStyleConfiguration.Title : _PrimitiveView {}
extension LabelStyleConfiguration.Icon : _PrimitiveView {}

extension LabelStyleConfiguration.Title {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        AnyView._makeView(view: view[\.view], inputs: inputs)
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        AnyView._makeViewList(view: view[\.view], inputs: inputs)
    }
}

extension LabelStyleConfiguration.Icon {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        AnyView._makeView(view: view[\.view], inputs: inputs)
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        AnyView._makeViewList(view: view[\.view], inputs: inputs)
    }
}

public struct DefaultLabelStyle : LabelStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

public struct IconOnlyLabelStyle : LabelStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
    }
}

public struct TitleAndIconLabelStyle : LabelStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

public struct TitleOnlyLabelStyle : LabelStyle {
    public init() {
    }
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

struct LabelStyleWritingModifier<Style>: ViewModifier where Style: LabelStyle {
    let style: Style
    typealias Body = Never
}

extension LabelStyleWritingModifier: _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.labelStyles.append(modifier[\.style].value)
    }
}

extension View {
    public func labelStyle<S>(_ style: S) -> some View where S : LabelStyle {
        modifier(LabelStyleWritingModifier(style: style))
    }
}
