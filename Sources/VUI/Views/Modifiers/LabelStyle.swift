//
//  File: LabelStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public protocol LabelStyle {
    associatedtype Body: View
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

extension LabelStyleConfiguration.Title: View {}
extension LabelStyleConfiguration.Icon: View {}
extension LabelStyleConfiguration.Title: _PrimitiveView {}
extension LabelStyleConfiguration.Icon: _PrimitiveView {}

extension LabelStyleConfiguration.Title {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

extension LabelStyleConfiguration.Icon {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
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
        fatalError("Implement with AG")
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

extension View {
    public func labelStyle<S>(_ style: S) -> some View where S: LabelStyle {
        modifier(LabelStyleWritingModifier(style: style))
    }
}
