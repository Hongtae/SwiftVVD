//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct _ViewModifier_Content<Modifier> where Modifier: ViewModifier {
    public typealias Body = Never
}

extension _ViewModifier_Content: View {
    public var body: Never { neverBody() }
}

public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder func body(content: Self.Content) -> Self.Body
    typealias Content = _ViewModifier_Content<Self>
}

extension ViewModifier where Self.Body == Never {
    public func body(content: Self.Content) -> Self.Body { neverBody() }
}

extension ViewModifier {
    public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public var body: Never { neverBody() }
}

extension ModifiedContent: _PrimitiveView where Content: View, Modifier: ViewModifier {
    func makeViewProxy(modifiers: [any ViewModifier],
                       environmentValues: EnvironmentValues,
                       sharedContext: SharedContext) -> any ViewProxy {
        var modifiers = modifiers
        modifiers.append(self.modifier)
        return _makeViewProxy(self.content,
                              modifiers: modifiers,
                              environmentValues: environmentValues,
                              sharedContext: sharedContext)
    }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        return ModifiedContent(content: self, modifier: modifier)
    }
}
