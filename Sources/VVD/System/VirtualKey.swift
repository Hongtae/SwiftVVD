//
//  File: VirtualKey.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public enum VirtualKey: Sendable {
    case none
    case escape
    case f1, f2, f3, f4
    case f5, f6, f7, f8
    case f9, f10, f11, f12
    case f13, f14, f15, f16
    case f17, f18, f19, f20
    case num0, num1, num2, num3, num4, num5, num6, num7, num8, num9 
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z

    case period
    case comma
    case slash
    case tab
    case accentTilde
    case backspace
    case semicolon
    case quote
    case backslash
    case equal
    case hyphen
    case space
    case openBracket
    case closeBracket
    case capslock

    case `return`

    case fn
    case insert
    case home
    case pageUp
    case pageDown
    case end
    case delete

    case left
    case right
    case up
    case down

    case leftShift
    case rightShift
    case leftOption
    case rightOption
    case leftControl
    case rightControl
    case leftCommand
    case rightCommand

    case pad0
    case pad1
    case pad2
    case pad3
    case pad4
    case pad5
    case pad6
    case pad7
    case pad8
    case pad9
    case enter
    case numlock
    case padSlash
    case padAsterisk
    case padPlus
    case padMinus
    case padEqual
    case padPeriod
}
