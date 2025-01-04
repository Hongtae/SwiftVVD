//
//  File: ButtonStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

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
        let view: ViewProxy?
    }
    public let role: ButtonRole?
    public let label: Label
    let action: ButtonAction
    public func trigger() {
        action()
    }
}

extension PrimitiveButtonStyleConfiguration.Label {
    init(_ view: ViewProxy? = nil) {
        self.view = view
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("WIP")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("WIP")
    }
}

extension PrimitiveButtonStyleConfiguration.Label : _PrimitiveView {}

public struct DefaultButtonStyle : PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
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
    public init() {}
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
    public init() {}
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
    public init() {}
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
    public init() {}
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
        let view: PrimitiveButtonStyleConfiguration.Label
    }
    public let role: ButtonRole?
    public let label: ButtonStyleConfiguration.Label
    public let isPressed: Bool
}

extension ButtonStyleConfiguration.Label {
    init(_ view: PrimitiveButtonStyleConfiguration.Label) {
        self.view = view
    }
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        PrimitiveButtonStyleConfiguration.Label._makeView(view: view[\.view], inputs: inputs)
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        PrimitiveButtonStyleConfiguration.Label._makeViewList(view: view[\.view], inputs: inputs)
    }
}

extension ButtonStyleConfiguration.Label : _PrimitiveView {}

struct _DefaultButtonWithButtonStyle<Style> : PrimitiveButtonStyle where Style: ButtonStyle {
    let style: Style

    func makeBody(configuration: Configuration) -> some View {
        let config = ButtonStyleConfiguration(role: configuration.role,
                                              label: .init(configuration.label),
                                              isPressed: false)

        return self.style.makeBody(configuration: config)._onButtonGesture {
            isPressed in

            // Update style
            Log.debug("button isPressed: \(isPressed)")
        } perform: {
            configuration.trigger()
        }
    }
}

struct PrimitiveButtonStyleContainerModifier<Style> : ViewModifier where Style : PrimitiveButtonStyle {
    let style: Style
    typealias Body = Never
}

struct PrimitiveButtonStyleProxy {
    let type: any PrimitiveButtonStyle.Type
    let graph: _GraphValue<Any>
    init<S : PrimitiveButtonStyle>(_ graph: _GraphValue<S>) {
        self.type = S.self
        self.graph = graph.unsafeCast(to: Any.self)
    }
    func resolve(_ view: ViewContext) -> any PrimitiveButtonStyle {
        fatalError()
    }
}

extension PrimitiveButtonStyleContainerModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("WIP")
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        fatalError("WIP")
    }
}

struct ButtonStyleContainerModifier<Style> : ViewModifier where Style : ButtonStyle {
    let style: Style
    typealias Body = Never

    var primitiveButtonStyle: some PrimitiveButtonStyle {
        _DefaultButtonWithButtonStyle(style: style)
    }

    var modifier: some ViewModifier {
        PrimitiveButtonStyleContainerModifier(style: primitiveButtonStyle)
    }

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("WIP")
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        fatalError("WIP")
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
