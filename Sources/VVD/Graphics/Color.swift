//
//  File: Color.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public struct Color: Hashable, Sendable {
    public var r : Scalar = 0.0
    public var g : Scalar = 0.0
    public var b : Scalar = 0.0
    public var a : Scalar = 1.0

    public typealias RGBA8 = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    public typealias ARGB8 = (a: UInt8, r: UInt8, g: UInt8, b: UInt8)

    public var rgba8 : RGBA8 {
        get { (r: UInt8(clamp(Int(self.r * 255.0), min: 0, max: 255)),
               g: UInt8(clamp(Int(self.g * 255.0), min: 0, max: 255)),
               b: UInt8(clamp(Int(self.b * 255.0), min: 0, max: 255)),
               a: UInt8(clamp(Int(self.a * 255.0), min: 0, max: 255))) }
        set(value) {
            let n: Scalar = 1.0 / 255.0
            self.r = Scalar(value.r) * n
            self.g = Scalar(value.g) * n
            self.b = Scalar(value.b) * n
            self.a = Scalar(value.a) * n
        }
    }

    public var argb8 : ARGB8 {
        get { (a: UInt8(clamp(Int(self.a * 255.0), min: 0, max: 255)),
               r: UInt8(clamp(Int(self.r * 255.0), min: 0, max: 255)),
               g: UInt8(clamp(Int(self.g * 255.0), min: 0, max: 255)),
               b: UInt8(clamp(Int(self.b * 255.0), min: 0, max: 255))) }
        set(value) {
            let n: Scalar = 1.0 / 255.0
            self.r = Scalar(value.r) * n
            self.g = Scalar(value.g) * n
            self.b = Scalar(value.b) * n
            self.a = Scalar(value.a) * n
        }
    }

    public var vector4: Vector4 {
        get { Vector4(self.r, self.g, self.b, self.a) }
        set(v) {
            self.r = v.x
            self.g = v.y
            self.b = v.z
            self.a = v.w
        }
    }

    public init<T: BinaryFloatingPoint>(_ r: T, _ g: T, _ b: T, _ a: T = 1) {
        self.r = Scalar(r)
        self.g = Scalar(g)
        self.b = Scalar(b)
        self.a = Scalar(a)
    }

    public init<T: BinaryFloatingPoint>(r: T, g: T, b: T, a: T = 1) {
        self.init(r, g, b, a)
    }

    public init(argb8: ARGB8) {
        self.argb8 = argb8
    }

    public init(rgba8: RGBA8) {
        self.rgba8 = rgba8
    }

    public init<T: BinaryFloatingPoint>(white: T, opacity: T = 1) {
        self.init(white, white, white, opacity)
    }

    public init<T: BinaryFloatingPoint>(hue: T,
                                        saturation: T,
                                        brightness: T,
                                        opacity: T = 1) {
        let hue = Scalar(hue).clamp(min: 0.0, max: 1.0)
        let saturation = Scalar(saturation).clamp(min: 0.0, max: 1.0)
        let brightness = Scalar(brightness).clamp(min: 0.0, max: 1.0)

        let c = saturation * brightness
        let h = Int(hue * 360) / 6
        let x = ((h % 2) == 0) ? 0: c
        let m = brightness - c

        let r, g, b: Scalar
        switch h {
        case 1:     (r, g, b) = (x, c, 0)
        case 2:     (r, g, b) = (0, c, x)
        case 3:     (r, g, b) = (0, x, c)
        case 4:     (r, g, b) = (x, 0, c)
        case 5:     (r, g, b) = (c, 0, x)
        default: // 0, 6
            (r, g, b) = (c, x, 0)
        }
        self.init(r + m, g + m, b + m, Scalar(opacity))
    }

    public init(rgbVector v: Vector3, alpha: some BinaryFloatingPoint = 1) {
        self.init(v.x, v.y, v.z, Scalar(alpha))
    }

    public init(rgbaVector v: Vector4) {
        self.init(v.x, v.y, v.z, v.w)
    }

    public func opacity(_ opacity: some BinaryFloatingPoint) -> Color {
        Color(self.r, self.g, self.b, Scalar(opacity))
    }

    public static let black = Color(0.0, 0.0, 0.0)
    public static let white = Color(1.0, 1.0, 1.0)
    public static let blue = Color(0.0, 0.0, 1.0)
    public static let brown = Color(0.6, 0.4, 0.2)
    public static let cyan = Color(0.0, 1.0, 1.0)
    public static let gray = Color(0.5, 0.5, 0.5)
    public static let darkGray = Color(0.3, 0.3, 0.3)
    public static let lightGray = Color(0.6, 0.6, 0.6)
    public static let green = Color(0.0, 1.0, 0.0)
    public static let magenta = Color(1.0, 0.0, 1.0)
    public static let orange = Color(1.0, 0.5, 0.0)
    public static let purple = Color(0.5, 0.0, 0.5)
    public static let red = Color(1.0, 0.0, 0.0)
    public static let yellow = Color(1.0, 1.0, 0.0)
    public static let clear = Color(0, 0, 0, 0)
}

public extension Color {
    var half4: Half4 {
        get {
            (Float16(self.r), Float16(self.g), Float16(self.b), Float16(self.a))
        }
        set(v) {
            self.r = Scalar(v.0)
            self.g = Scalar(v.1)
            self.b = Scalar(v.2)
            self.a = Scalar(v.3)
        }
    }

    var float4: Float4 {
        get {
            (Float32(self.r), Float32(self.g), Float32(self.b), Float32(self.a))
        }
        set(v) {
            self.r = Scalar(v.0)
            self.g = Scalar(v.1)
            self.b = Scalar(v.2)
            self.a = Scalar(v.3)
        }
    }

    var double4: Double4 {
        get {
            (Float64(self.r), Float64(self.g), Float64(self.b), Float64(self.a))
        }
        set(v) {
            self.r = Scalar(v.0)
            self.g = Scalar(v.1)
            self.b = Scalar(v.2)
            self.a = Scalar(v.3)
        }
    }
}
