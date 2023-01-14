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
    public static let red = Color(red: 1, green: 0.231373, blue: 0.188235)
    public static let orange = Color(red: 1, green: 0.584314, blue: 0)
    public static let yellow = Color(red: 1, green: 0.8, blue: 0)
    public static let green = Color(red: 0.156863, green: 0.803922, blue: 0.254902)
    public static let mint = Color(red: 0, green: 0.780392, blue: 0.745098)
    public static let teal = Color(red: 0.34902, green: 0.678431, blue: 0.768627)
    public static let cyan = Color(red: 0.333333, green: 0.745098, blue: 0.941176)
    public static let blue = Color(red: 0, green: 0.478431, blue: 1)
    public static let indigo = Color(red: 0.345098, green: 0.337255, blue: 0.839216)
    public static let purple = Color(red: 0.686275, green: 0.321569, blue: 0.870588)
    public static let pink = Color(red: 1, green: 0.176471, blue: 0.333333)
    public static let brown = Color(red: 0.635294, green: 0.517647, blue: 0.368627)
    public static let white = Color(red: 1, green: 1, blue: 1)
    public static let gray = Color(red: 0.556863, green: 0.556863, blue: 0.576471)
    public static let black = Color(red: 0, green: 0, blue: 0)
    public static let clear = Color(red: 0, green: 0, blue: 0, opacity: 0)
    public static let primary = Color(red: 0, green: 0, blue: 0, opacity: 0.847059)
    public static let secondary = Color(red: 0, green: 0, blue: 0, opacity: 0.498039)
}

extension Color: ShapeStyle {
}
