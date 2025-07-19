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
    }
    
    public struct Content: View {
        public typealias Body = Never
    }
}

extension MenuStyleConfiguration.Label: _PrimitiveView {}
extension MenuStyleConfiguration.Content: _PrimitiveView {}

extension View {
    public func menuStyle<S>(_ style: S) -> some View where S: MenuStyle {
        fatalError()
    }
}

public struct DefaultMenuStyle: MenuStyle {
    public init() {
    }
    
    public func makeBody(configuration: DefaultMenuStyle.Configuration) -> some View {
        fatalError()
    }
}

extension MenuStyle where Self == DefaultMenuStyle {
    public static var automatic: DefaultMenuStyle {
        .init()
    }
}
