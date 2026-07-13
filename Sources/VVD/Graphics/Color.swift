//
//  File: Color.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public enum RGBPrimaries: Hashable, Sendable {
    case sRGB
    case displayP3
}

public enum RGBTransferFunction: Hashable, Sendable {
    case linear
    case sRGB
}

public struct RGBColorSpaceDescriptor: Hashable, Sendable {
    public let primaries: RGBPrimaries
    public let transferFunction: RGBTransferFunction

    public init(
        primaries: RGBPrimaries,
        transferFunction: RGBTransferFunction
    ) {
        self.primaries = primaries
        self.transferFunction = transferFunction
    }
}

public protocol RGBColorSpace: Sendable {
    static var descriptor: RGBColorSpaceDescriptor { get }
}

public enum SRGB: RGBColorSpace {
    public static let descriptor = RGBColorSpaceDescriptor(
        primaries: .sRGB,
        transferFunction: .sRGB
    )
}

public enum LinearSRGB: RGBColorSpace {
    public static let descriptor = RGBColorSpaceDescriptor(
        primaries: .sRGB,
        transferFunction: .linear
    )
}

public enum DisplayP3: RGBColorSpace {
    public static let descriptor = RGBColorSpaceDescriptor(
        primaries: .displayP3,
        transferFunction: .sRGB
    )
}

public enum LinearDisplayP3: RGBColorSpace {
    public static let descriptor = RGBColorSpaceDescriptor(
        primaries: .displayP3,
        transferFunction: .linear
    )
}

/// RGBA components whose RGB interpretation is fixed by the generic space.
/// Alpha is always a linear, unassociated coverage value.
public struct Color<Space: RGBColorSpace>: Hashable, Sendable {
    /// Four unassociated 8-bit components interpreted in `Space`.
    public struct RGBA8: Hashable, Sendable {
        public var r: UInt8
        public var g: UInt8
        public var b: UInt8
        public var a: UInt8

        public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }
    }

    /// Four unassociated 8-bit components interpreted in `Space`.
    public struct ARGB8: Hashable, Sendable {
        public var a: UInt8
        public var r: UInt8
        public var g: UInt8
        public var b: UInt8

        public init(a: UInt8, r: UInt8, g: UInt8, b: UInt8) {
            self.a = a
            self.r = r
            self.g = g
            self.b = b
        }
    }

    public var r: Scalar
    public var g: Scalar
    public var b: Scalar
    public var a: Scalar

    public static var colorSpace: RGBColorSpaceDescriptor {
        Space.descriptor
    }

    public var colorSpace: RGBColorSpaceDescriptor {
        Self.colorSpace
    }

    public var rgba8: RGBA8 {
        get {
            RGBA8(
                r: Self.quantized8(r),
                g: Self.quantized8(g),
                b: Self.quantized8(b),
                a: Self.quantized8(a)
            )
        }
        set {
            let scale: Scalar = 1 / 255
            r = Scalar(newValue.r) * scale
            g = Scalar(newValue.g) * scale
            b = Scalar(newValue.b) * scale
            a = Scalar(newValue.a) * scale
        }
    }

    public var argb8: ARGB8 {
        get {
            ARGB8(
                a: Self.quantized8(a),
                r: Self.quantized8(r),
                g: Self.quantized8(g),
                b: Self.quantized8(b)
            )
        }
        set {
            let scale: Scalar = 1 / 255
            r = Scalar(newValue.r) * scale
            g = Scalar(newValue.g) * scale
            b = Scalar(newValue.b) * scale
            a = Scalar(newValue.a) * scale
        }
    }

    public var vector4: Vector4 {
        get { Vector4(r, g, b, a) }
        set {
            r = newValue.x
            g = newValue.y
            b = newValue.z
            a = newValue.w
        }
    }

    public init<T: BinaryFloatingPoint>(
        _ r: T,
        _ g: T,
        _ b: T,
        _ a: T = 1
    ) {
        self.r = Scalar(r)
        self.g = Scalar(g)
        self.b = Scalar(b)
        self.a = Scalar(a)
    }

    public init<T: BinaryFloatingPoint>(
        r: T,
        g: T,
        b: T,
        a: T = 1
    ) {
        self.init(r, g, b, a)
    }

    public init(argb8: ARGB8) {
        let scale: Scalar = 1 / 255
        r = Scalar(argb8.r) * scale
        g = Scalar(argb8.g) * scale
        b = Scalar(argb8.b) * scale
        a = Scalar(argb8.a) * scale
    }

    public init(rgba8: RGBA8) {
        let scale: Scalar = 1 / 255
        r = Scalar(rgba8.r) * scale
        g = Scalar(rgba8.g) * scale
        b = Scalar(rgba8.b) * scale
        a = Scalar(rgba8.a) * scale
    }

    public init<T: BinaryFloatingPoint>(white: T, opacity: T = 1) {
        self.init(white, white, white, opacity)
    }

    public init<T: BinaryFloatingPoint>(
        hue: T,
        saturation: T,
        brightness: T,
        opacity: T = 1
    ) {
        let hue = Scalar(hue).clamp(min: 0, max: 1)
        let saturation = Scalar(saturation).clamp(min: 0, max: 1)
        let brightness = Scalar(brightness).clamp(min: 0, max: 1)
        let sectorValue = hue == 1 ? 0 : hue * 6
        let sector = Int(sectorValue)
        let fraction = sectorValue - Scalar(sector)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))

        let r, g, b: Scalar
        switch sector {
        case 0: (r, g, b) = (brightness, t, p)
        case 1: (r, g, b) = (q, brightness, p)
        case 2: (r, g, b) = (p, brightness, t)
        case 3: (r, g, b) = (p, q, brightness)
        case 4: (r, g, b) = (t, p, brightness)
        default: (r, g, b) = (brightness, p, q)
        }
        self.init(r, g, b, Scalar(opacity))
    }

    public init(rgbVector value: Vector3, alpha: some BinaryFloatingPoint = 1) {
        self.init(value.x, value.y, value.z, Scalar(alpha))
    }

    public init(rgbaVector value: Vector4) {
        self.init(value.x, value.y, value.z, value.w)
    }

    public func opacity(_ opacity: some BinaryFloatingPoint) -> Self {
        Self(r, g, b, Scalar(opacity))
    }

    public func converted<Destination: RGBColorSpace>(
        to _: Destination.Type
    ) -> Color<Destination> {
        let components = convertRGBComponents(
            (r, g, b),
            from: Space.descriptor,
            to: Destination.descriptor
        )
        return Color<Destination>(components.0, components.1, components.2, a)
    }

    public var sRGB: Color<SRGB> {
        converted(to: SRGB.self)
    }

    public var linearSRGB: Color<LinearSRGB> {
        converted(to: LinearSRGB.self)
    }

    public var displayP3: Color<DisplayP3> {
        converted(to: DisplayP3.self)
    }

    public var linearDisplayP3: Color<LinearDisplayP3> {
        converted(to: LinearDisplayP3.self)
    }

    public var anyColor: AnyColor {
        AnyColor(self)
    }

    private static func quantized8(_ value: Scalar) -> UInt8 {
        UInt8(clamp(Int(value * 255), min: 0, max: 255))
    }
}

public extension Color {
    /// Raw components in `Space`; no color conversion or premultiplication occurs.
    var half4: Half4 {
        get {
            (Float16(r), Float16(g), Float16(b), Float16(a))
        }
        set {
            r = Scalar(newValue.0)
            g = Scalar(newValue.1)
            b = Scalar(newValue.2)
            a = Scalar(newValue.3)
        }
    }

    /// Raw components in `Space`; no color conversion or premultiplication occurs.
    var float4: Float4 {
        get {
            (Float32(r), Float32(g), Float32(b), Float32(a))
        }
        set {
            r = Scalar(newValue.0)
            g = Scalar(newValue.1)
            b = Scalar(newValue.2)
            a = Scalar(newValue.3)
        }
    }

    /// Raw components in `Space`; no color conversion or premultiplication occurs.
    var double4: Double4 {
        get {
            (Float64(r), Float64(g), Float64(b), Float64(a))
        }
        set {
            r = Scalar(newValue.0)
            g = Scalar(newValue.1)
            b = Scalar(newValue.2)
            a = Scalar(newValue.3)
        }
    }
}

public extension Color {
    // These are raw component-space constants. Convert an explicitly chosen
    // source color when appearance must remain invariant across spaces.
    static var black: Self { Self(0, 0, 0) }
    static var white: Self { Self(1, 1, 1) }
    static var blue: Self { Self(0, 0, 1) }
    static var brown: Self { Self(0.6, 0.4, 0.2) }
    static var cyan: Self { Self(0, 1, 1) }
    static var gray: Self { Self(0.5, 0.5, 0.5) }
    static var darkGray: Self { Self(0.3, 0.3, 0.3) }
    static var lightGray: Self { Self(0.6, 0.6, 0.6) }
    static var green: Self { Self(0, 1, 0) }
    static var magenta: Self { Self(1, 0, 1) }
    static var mint: Self { Self(0, 0.780392, 0.745098) }
    static var orange: Self { Self(1, 0.5, 0) }
    static var purple: Self { Self(0.5, 0, 0.5) }
    static var red: Self { Self(1, 0, 0) }
    static var yellow: Self { Self(1, 1, 0) }
    static var clear: Self { Self(0, 0, 0, 0) }
}

public typealias SRGBColor = Color<SRGB>
public typealias LinearSRGBColor = Color<LinearSRGB>
public typealias DisplayP3Color = Color<DisplayP3>
public typealias LinearDisplayP3Color = Color<LinearDisplayP3>

/// A runtime-space color for storage and heterogeneous collections.
public struct AnyColor: Hashable, Sendable {
    public var r: Scalar
    public var g: Scalar
    public var b: Scalar
    public var a: Scalar
    public let colorSpace: RGBColorSpaceDescriptor

    public init<T: BinaryFloatingPoint>(
        _ r: T,
        _ g: T,
        _ b: T,
        _ a: T = 1,
        colorSpace: RGBColorSpaceDescriptor
    ) {
        self.r = Scalar(r)
        self.g = Scalar(g)
        self.b = Scalar(b)
        self.a = Scalar(a)
        self.colorSpace = colorSpace
    }

    public init<Space: RGBColorSpace>(_ color: Color<Space>) {
        r = color.r
        g = color.g
        b = color.b
        a = color.a
        colorSpace = Space.descriptor
    }

    public func converted<Destination: RGBColorSpace>(
        to _: Destination.Type
    ) -> Color<Destination> {
        let components = convertRGBComponents(
            (r, g, b),
            from: colorSpace,
            to: Destination.descriptor
        )
        return Color<Destination>(components.0, components.1, components.2, a)
    }

    public var sRGB: Color<SRGB> {
        converted(to: SRGB.self)
    }

    public var linearSRGB: Color<LinearSRGB> {
        converted(to: LinearSRGB.self)
    }

    public var displayP3: Color<DisplayP3> {
        converted(to: DisplayP3.self)
    }

    public var linearDisplayP3: Color<LinearDisplayP3> {
        converted(to: LinearDisplayP3.self)
    }

    public func opacity(_ opacity: some BinaryFloatingPoint) -> Self {
        Self(r, g, b, Scalar(opacity), colorSpace: colorSpace)
    }

    public var vector4: Vector4 {
        get { Vector4(r, g, b, a) }
        set {
            r = newValue.x
            g = newValue.y
            b = newValue.z
            a = newValue.w
        }
    }

    public var half4: Half4 {
        (Float16(r), Float16(g), Float16(b), Float16(a))
    }

    public var float4: Float4 {
        (Float32(r), Float32(g), Float32(b), Float32(a))
    }

    public var double4: Double4 {
        (Float64(r), Float64(g), Float64(b), Float64(a))
    }

    public static let clear = AnyColor(Color<LinearSRGB>.clear)
}

private func convertRGBComponents(
    _ components: (Scalar, Scalar, Scalar),
    from source: RGBColorSpaceDescriptor,
    to destination: RGBColorSpaceDescriptor
) -> (Scalar, Scalar, Scalar) {
    guard source != destination else { return components }

    let linearSource = (
        decodeTransfer(components.0, source.transferFunction),
        decodeTransfer(components.1, source.transferFunction),
        decodeTransfer(components.2, source.transferFunction)
    )
    let linearDestination: (Scalar, Scalar, Scalar)
    if source.primaries == destination.primaries {
        linearDestination = linearSource
    } else {
        let xyz = linearRGBToXYZ(linearSource, source.primaries)
        linearDestination = xyzToLinearRGB(xyz, destination.primaries)
    }
    return (
        encodeTransfer(linearDestination.0, destination.transferFunction),
        encodeTransfer(linearDestination.1, destination.transferFunction),
        encodeTransfer(linearDestination.2, destination.transferFunction)
    )
}

private func decodeTransfer(
    _ component: Scalar,
    _ transferFunction: RGBTransferFunction
) -> Scalar {
    guard transferFunction == .sRGB else { return component }
    let magnitude = abs(component)
    if magnitude <= 0.04045 {
        return component / 12.92
    }
    let result = pow((magnitude + 0.055) / 1.055, 2.4)
    return component < 0 ? -result : result
}

private func encodeTransfer(
    _ component: Scalar,
    _ transferFunction: RGBTransferFunction
) -> Scalar {
    guard transferFunction == .sRGB else { return component }
    let magnitude = abs(component)
    if magnitude <= 0.0031308 {
        return component * 12.92
    }
    let result = 1.055 * pow(magnitude, 1 / 2.4) - 0.055
    return component < 0 ? -result : result
}

private func linearRGBToXYZ(
    _ rgb: (Scalar, Scalar, Scalar),
    _ primaries: RGBPrimaries
) -> (Scalar, Scalar, Scalar) {
    // Exact D65 matrices from the standard sRGB and Display P3 primaries.
    switch primaries {
    case .sRGB:
        return multiply(
            (
                (506752 / 1228815, 87881 / 245763, 12673 / 70218),
                (87098 / 409605, 175762 / 245763, 12673 / 175545),
                (7918 / 409605, 87881 / 737289, 1001167 / 1053270)
            ),
            rgb
        )
    case .displayP3:
        return multiply(
            (
                (608311 / 1250200, 189793 / 714400, 198249 / 1000160),
                (35783 / 156275, 247089 / 357200, 198249 / 2500400),
                (0, 32229 / 714400, 5220557 / 5000800)
            ),
            rgb
        )
    }
}

private func xyzToLinearRGB(
    _ xyz: (Scalar, Scalar, Scalar),
    _ primaries: RGBPrimaries
) -> (Scalar, Scalar, Scalar) {
    switch primaries {
    case .sRGB:
        return multiply(
            (
                (12831 / 3959, -329 / 214, -1974 / 3959),
                (-851781 / 878810, 1648619 / 878810, 36519 / 878810),
                (705 / 12673, -2585 / 12673, 705 / 667)
            ),
            xyz
        )
    case .displayP3:
        return multiply(
            (
                (446124 / 178915, -333277 / 357830, -72051 / 178915),
                (-14852 / 17905, 63121 / 35810, 423 / 17905),
                (11844 / 330415, -50337 / 660830, 316169 / 330415)
            ),
            xyz
        )
    }
}

private func multiply(
    _ matrix: (
        (Scalar, Scalar, Scalar),
        (Scalar, Scalar, Scalar),
        (Scalar, Scalar, Scalar)
    ),
    _ vector: (Scalar, Scalar, Scalar)
) -> (Scalar, Scalar, Scalar) {
    (
        matrix.0.0 * vector.0 + matrix.0.1 * vector.1 + matrix.0.2 * vector.2,
        matrix.1.0 * vector.0 + matrix.1.1 * vector.1 + matrix.1.2 * vector.2,
        matrix.2.0 * vector.0 + matrix.2.1 * vector.1 + matrix.2.2 * vector.2
    )
}
