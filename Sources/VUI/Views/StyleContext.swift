//
//  File: StyleContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol StyleContext: Sendable {
    static func _isModifierAllowed<T: ViewModifier>(_: T.Type) -> Bool

    var minimumViewSize: CGSize { get }
    var maximumViewSize: CGSize { get }
    
    var foregroundStyle: any ShapeStyle { get }
    var backgroundStyle: any ShapeStyle { get }
    
    var textOffset: Int { get }
    var buttonStyle: (any StyleContext)? { get }
    var buttonHighlightStyle: (any StyleContext)? { get }
}

extension StyleContext {
    static func _isModifierAllowed<T: ViewModifier>(_: T.Type) -> Bool {
        true
    }

    var minimumViewSize: CGSize { CGSize(width: 0, height: 0) }
    var maximumViewSize: CGSize { CGSize(width: Int.max, height: Int.max) }
    var foregroundStyle: any ShapeStyle { .foreground }
    var backgroundStyle: any ShapeStyle { .background }

    var textOffset: Int { 0 }
    var buttonStyle: (any StyleContext)? { nil }
    var buttonHighlightStyle: (any StyleContext)? { nil }
}

private protocol _MenuItemStyleContext: StyleContext {
}

extension _MenuItemStyleContext {
    static func _isModifierAllowed<T: ViewModifier>(_: T.Type) -> Bool {
        if T.self is any _ViewInputsModifier.Type { return true }
        if T.self is any _GraphInputsModifier.Type { return true }
        // only buttons are allowed.
        if let gestureModifier = T.self as? any _GestureGenerator.Type {
            func isButton<U: _GestureGenerator>(_ type: U.Type) -> Bool {
                U.T.self is _ButtonGesture.Type
            }
            if isButton(gestureModifier) { return true }
        }
        return false
    }
    
    var minimumViewSize: CGSize { CGSize(width: 120, height: 24) }
    var maximumViewSize: CGSize { CGSize(width: 200, height: 200) }
    var foregroundStyle: any ShapeStyle { Color.gray }
    var backgroundStyle: any ShapeStyle { .background }

    var textOffset: Int { 4 }
    var buttonStyle: (any StyleContext)? { MenuButtonStyleContext() }
    var buttonHighlightStyle: (any StyleContext)? { MenuButtonHighlightStyleContext() }
}

struct MenuStyleContext: _MenuItemStyleContext {
}

struct MenuButtonStyleContext: _MenuItemStyleContext {
    var foregroundStyle: any ShapeStyle { .foreground }
    var backgroundStyle: any ShapeStyle { .background }
}

struct MenuButtonHighlightStyleContext: _MenuItemStyleContext {
    var foregroundStyle: any ShapeStyle { .white }
    var backgroundStyle: any ShapeStyle { .background }
}

private struct _OverrideStyleContextKey: EnvironmentKey {
    static let defaultValue: (any StyleContext)? = nil
}

extension EnvironmentValues {
    var _overrideStyleContext: (any StyleContext)? {
        get { self[_OverrideStyleContextKey.self] }
        set { self[_OverrideStyleContextKey.self] = newValue }
    }
}
