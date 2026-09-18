//
//  File: TextForegroundStyleModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

final class TextForegroundStyleModifier: AnyTextModifier {
    let style: AnyShapeStyle

    init<S: ShapeStyle>(_ style: S) { self.style = AnyShapeStyle(style) }

    override func modify(style: inout Text.Style, environment: EnvironmentValues) {
        style.color = .explicit(self.style.copyStyle(in: environment,
            foregroundStyle: style.color.baseStyle(in: environment)))
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        guard let other = other as? TextForegroundStyleModifier else { return false }
        return style.storage == other.style.storage
    }
}

final class TextForegroundKeyColorModifier: AnyTextModifier, @unchecked Sendable {
    static let shared = TextForegroundKeyColorModifier()

    override func modify(style: inout Text.Style, environment: EnvironmentValues) {
        style.color = .foregroundKeyColor(base: style.color.baseStyle(in: environment))
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        other is TextForegroundKeyColorModifier
    }
}
