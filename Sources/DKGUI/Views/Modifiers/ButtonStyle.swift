//
//  File: ButtonStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public protocol PrimitiveButtonStyle {
    associatedtype Body : View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = PrimitiveButtonStyleConfiguration
}

public struct ButtonRole : Equatable, Sendable {
    public static let destructive = ButtonRole(_role: .destructive)
    public static let cancel = ButtonRole(_role: .cancel)

    enum Role : UInt8 {
        case destructive = 1
        case cancel = 4
    }
    let _role: Role
}

typealias ButtonAction = ()->Void

public struct PrimitiveButtonStyleConfiguration {
    public struct Label : View {
        public typealias Body = Never
        let view: AnyView
    }
    public let role: ButtonRole?
    public let label: PrimitiveButtonStyleConfiguration.Label
    let action: ButtonAction
    public func trigger() {
        action()
    }
}

extension PrimitiveButtonStyleConfiguration.Label : _PrimitiveView {}

extension PrimitiveButtonStyleConfiguration.Label {
    init() {
        self.view = AnyView(EmptyView())
    }
    init(_ view: AnyView) {
        self.view = view
    }
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        AnyView._makeView(view: view[\.view], inputs: inputs)
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        AnyView._makeViewList(view: view[\.view], inputs: inputs)
    }
}

public struct DefaultButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        //TODO: Use .background, .foreground styles instead of specific colors.
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius:4).fill(.white)
                RoundedRectangle(cornerRadius:4).strokeBorder(.black)
            }
            .foregroundStyle(.black)
            ._onButtonGesture {
                configuration.trigger()
            }
    }
}

public struct BorderlessButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius:4).fill(.white)
            }
            ._onButtonGesture {
                configuration.trigger()
            }
    }
}

public struct LinkButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius:4).strokeBorder(.black)
            }
            ._onButtonGesture {
                configuration.trigger()
            }
    }
}

public struct PlainButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius:4).strokeBorder(.black)
            }
            ._onButtonGesture {
                configuration.trigger()
            }
    }
}

public struct BorderedButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius:4).strokeBorder(.black)
            }
            ._onButtonGesture {
                configuration.trigger()
            }
    }
}

extension PrimitiveButtonStyle where Self == DefaultButtonStyle {
    public static var automatic: DefaultButtonStyle { .init() }
}

extension PrimitiveButtonStyle where Self == BorderlessButtonStyle {
    public static var borderless: BorderlessButtonStyle { .init() }
}

extension PrimitiveButtonStyle where Self == LinkButtonStyle {
    public static var link: LinkButtonStyle { .init() }
}

extension PrimitiveButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { .init() }
}

extension PrimitiveButtonStyle where Self == BorderedButtonStyle {
    public static var bordered: BorderedButtonStyle { .init() }
}

public protocol ButtonStyle {
    associatedtype Body : View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ButtonStyleConfiguration
}

public struct ButtonStyleConfiguration {
    public struct Label : View {
        public typealias Body = Never
        let view: AnyView
    }
    public let role: ButtonRole?
    public let label: ButtonStyleConfiguration.Label
    public let isPressed: Bool
}

extension ButtonStyleConfiguration.Label : _PrimitiveView {}

extension ButtonStyleConfiguration.Label {
    init(_ view: AnyView) {
        self.view = view
    }
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        AnyView._makeView(view: view[\.view], inputs: inputs)
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        AnyView._makeViewList(view: view[\.view], inputs: inputs)
    }
}

struct _DefaultButtonWithButtonStyle<Style> : PrimitiveButtonStyle where Style: ButtonStyle {
    let style: Style
    public init(style: Style) {
        self.style = style
    }
    public func makeBody(configuration: Configuration) -> some View {
        let btnConfig = ButtonStyleConfiguration(role: configuration.role,
                                                 label: .init(configuration.label.view),
                                                 isPressed: false)
        return self.style.makeBody(configuration: btnConfig)._onButtonGesture {
            configuration.trigger()
        }
    }
}

struct PrimitiveButtonStyleContainerModifier<Style> : ViewModifier where Style: PrimitiveButtonStyle {
    let style: Style
    typealias Body = Never
}

extension PrimitiveButtonStyleContainerModifier: _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.primitiveButtonStyles.append(modifier[\.style].value)
    }
}

struct ButtonStyleContainerModifier<Style> : ViewModifier where Style: ButtonStyle {
    let style: Style
    typealias Body = Never
}

extension ButtonStyleContainerModifier: _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.primitiveButtonStyles.append(_DefaultButtonWithButtonStyle(style: modifier[\.style].value))
    }
}

extension View {
    public func buttonStyle<S>(_ style: S) -> some View where S : PrimitiveButtonStyle {
        modifier(PrimitiveButtonStyleContainerModifier(style: style))
    }

    public func buttonStyle<S>(_ style: S) -> some View where S : ButtonStyle {
        modifier(ButtonStyleContainerModifier(style: style))
    }
}
