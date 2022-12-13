//
//  File: Color.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct Color {
    public enum RGBColorSpace: Equatable, Hashable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

    public init(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        fatalError()
    }

    public init(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        fatalError()
    }

    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        fatalError()
    }

    public func opacity(_ opacity: Double) -> Color {
        fatalError()
    }

    public init() {
        fatalError()
    }
}

extension Color {
    public static let red = Color()
    public static let orange = Color()
    public static let yellow = Color()
    public static let green = Color()
    public static let mint = Color()
    public static let teal = Color()
    public static let cyan = Color()
    public static let blue = Color()
    public static let indigo = Color()
    public static let purple = Color()
    public static let pink = Color()
    public static let brown = Color()
    public static let white = Color()
    public static let gray = Color()
    public static let black = Color()
    public static let clear = Color()
    public static let primary = Color()
    public static let secondary = Color()
}
