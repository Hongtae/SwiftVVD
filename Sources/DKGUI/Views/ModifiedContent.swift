//
//  File: ModifiedContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct ModifiedContent<Content, Modifier> {
    public typealias Body = Never

    public var content: Content
    public var modifier: Modifier

    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
}

extension ModifiedContent: Equatable where Content: Equatable, Modifier: Equatable {
    public static func == (a: ModifiedContent<Content, Modifier>, b: ModifiedContent<Content, Modifier>) -> Bool {
        return a.content == b.content && a.modifier == b.modifier
    }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public var body: Never { neverBody() }
}

extension ModifiedContent: _PrimitiveView where Content: View, Modifier: ViewModifier {
    func makeViewProxy(modifiers: [any ViewModifier], environmentValues: EnvironmentValues) -> any ViewProxy {
        var modifiers = modifiers
        modifiers.append(self.modifier)
        return _makeViewProxy(self.content, modifiers: modifiers, environmentValues: environmentValues)
    }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        return ModifiedContent(content: self, modifier: modifier)
    }
}
