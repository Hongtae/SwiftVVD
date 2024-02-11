//
//  File: ButtonStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
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
    }
    public let role: ButtonRole?
    public let label: PrimitiveButtonStyleConfiguration.Label
    let action: ButtonAction
    public func trigger() {
        action()
    }
}

extension PrimitiveButtonStyleConfiguration.Label : _PrimitiveView {}

public struct DefaultButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        fatalError()
    }
    //public typealias Body = @_opaqueReturnTypeOf("$s7SwiftUI18DefaultButtonStyleV8makeBody13configurationQrAA09PrimitivedE13ConfigurationV_tF", 0) __
}

public struct BorderlessButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        fatalError()
    }
    //public typealias Body = @_opaqueReturnTypeOf("$s7SwiftUI21BorderlessButtonStyleV8makeBody13configurationQrAA09PrimitivedE13ConfigurationV_tF", 0) __
}

public struct LinkButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        fatalError()
    }
    //public typealias Body = @_opaqueReturnTypeOf("$s7SwiftUI15LinkButtonStyleV8makeBody13configurationQrAA09PrimitivedE13ConfigurationV_tF", 0) __
}

public struct PlainButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
        fatalError()
    }
    //public typealias Body = @_opaqueReturnTypeOf("$s7SwiftUI16PlainButtonStyleV8makeBody13configurationQrAA09PrimitivedE13ConfigurationV_tF", 0) __
}

public struct BorderedButtonStyle : PrimitiveButtonStyle {
    public init() {
    }
    public func makeBody(configuration: Configuration) -> some View {
    }
    //public typealias Body = @_opaqueReturnTypeOf("$s7SwiftUI19BorderedButtonStyleV8makeBody13configurationQrAA09PrimitivedE13ConfigurationV_tF", 0) __
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
    }
    public let role: ButtonRole?
    public let label: ButtonStyleConfiguration.Label
    public let isPressed: Bool
}

extension ButtonStyleConfiguration.Label : _PrimitiveView {}

struct PrimitiveButtonStyleContainerModifier<Style> : ViewModifier where Style: PrimitiveButtonStyle {
    let style: Style
    typealias Body = Never
}

struct ButtonStyleContainerModifier<Style> : ViewModifier where Style: ButtonStyle {
    let style: Style
    typealias Body = Never
}

extension View {
    public func buttonStyle<S>(_ style: S) -> some View where S : PrimitiveButtonStyle {
        modifier(PrimitiveButtonStyleContainerModifier(style: style))
    }

    public func buttonStyle<S>(_ style: S) -> some View where S : ButtonStyle {
        modifier(ButtonStyleContainerModifier(style: style))
    }
}
