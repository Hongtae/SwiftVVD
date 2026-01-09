//
//  File: StyleContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

protocol StyleContext {
    static func _isModifierAllowed<T: ViewModifier>(_: T.Type) -> Bool
    var viewStyleSheet: ViewStyleSheet { get }
}

struct MenuStyleContext: StyleContext {
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

    var viewStyleSheet: ViewStyleSheet {
        ViewStyleSheet(minimumViewSize: CGSize(width: 44, height: 44),
                       maximumViewSize: CGSize(width: 100, height: 44))
    }
}

struct ViewStyleSheet {
    let minimumViewSize: CGSize
    let maximumViewSize: CGSize
}
