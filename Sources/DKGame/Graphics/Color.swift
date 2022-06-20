//
//  File: Color.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct Color {
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

    public init(_ r: Scalar, _ g: Scalar, _ b: Scalar, _ a: Scalar = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(r: Scalar, g: Scalar, b: Scalar, a: Scalar = 1.0) {
        self.init(r, g, b, a)
    }

    public static let black: Color = .init(0.0, 0.0, 0.0, 1.0)
    public static let white: Color = .init(1.0, 1.0, 1.0, 1.0)
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
