//
//  File: StyleContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol StyleContext: Sendable {
    var minimumViewSize: CGSize { get }
    var maximumViewSize: CGSize { get }

    var foregroundStyle: any ShapeStyle { get }
    var backgroundStyle: any ShapeStyle { get }

    var textOffset: Int { get }
    var buttonStyle: (any StyleContext)? { get }
    var buttonHighlightStyle: (any StyleContext)? { get }
}

extension StyleContext {
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

struct _SubmenuRegistration: @unchecked Sendable {
    var close: () -> Void
    var isHovered: () -> Bool
}

class MenuContext: @unchecked Sendable {
    var activeSubmenuRegistration: _SubmenuRegistration? = nil
}

private struct _MenuContextKey: EnvironmentKey {
    static let defaultValue: MenuContext? = nil
}

extension EnvironmentValues {
    var _menuContext: MenuContext? {
        get { self[_MenuContextKey.self] }
        set { self[_MenuContextKey.self] = newValue }
    }
}
