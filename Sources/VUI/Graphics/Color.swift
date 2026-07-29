//
//  File: Color.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// The current non-linear renderer consumes encoded sRGB components.
typealias BackendColor = VVD.Color<VVD.SRGB>

private struct ColorComponents: Hashable, Sendable {
    var colorSpace: Color.RGBColorSpace
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    func resolve() -> Color.Resolved {
        Color.Resolved(
            colorSpace: colorSpace,
            red: Float(red),
            green: Float(green),
            blue: Float(blue),
            opacity: Float(alpha)
        )
    }
}

private protocol ColorProvider: Hashable {
    // Components provide the stable light/standard representation used by
    // environment-free display-list inspection and interpolation.
    var components: ColorComponents { get }
    var description: String { get }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved
    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR
    func isEqual(to other: any ColorProvider) -> Bool
}

private extension ColorProvider {
    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        components.resolve()
    }

    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        Color.ResolvedHDR(resolve(in: environment))
    }

    func isEqual(to other: any ColorProvider) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

private struct RGBColorProvider: ColorProvider {
    var components: ColorComponents

    var description: String {
        if components.colorSpace == .displayP3 {
            return "DisplayP3(red: \(components.red), green: \(components.green), blue: \(components.blue), opacity: \(components.alpha))"
        }
        let resolved = components.resolve()
        return String(
            format: "#%02X%02X%02X%02X",
            Self.descriptionComponent(resolved.red),
            Self.descriptionComponent(resolved.green),
            Self.descriptionComponent(resolved.blue),
            Self.descriptionComponent(resolved.opacity)
        )
    }

    private static func descriptionComponent(_ value: Float) -> Int32 {
        Int32(value * 255 + 0.5)
    }
}

private struct OpacityColor: ColorProvider {
    var base: Color
    var opacity: Double

    var components: ColorComponents {
        var components = base.provider.components
        components.alpha *= opacity
        return components
    }

    var description: String {
        "\(Int(opacity * 100 + 0.5))% \(base.description)"
    }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        var resolved = base.resolve(in: environment)
        resolved.opacity *= Float(opacity)
        return resolved
    }

    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        var resolved = base.resolveHDR(in: environment)
        resolved.opacity *= Float(opacity)
        return resolved
    }
}

private struct ResolvedHDRColorProvider: ColorProvider {
    var color: Color.ResolvedHDR

    var components: ColorComponents {
        ColorComponents(
            colorSpace: .sRGBLinear,
            red: Double(color.linearRed),
            green: Double(color.linearGreen),
            blue: Double(color.linearBlue),
            alpha: Double(color.opacity)
        )
    }

    var description: String {
        color.description
    }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        color.base
    }

    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        color
    }
}

private enum SystemColorType: String, ColorProvider, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue
    case indigo, purple, pink, brown, white, gray, black, clear
    case primary, secondary

    var components: ColorComponents {
        components(scheme: .light, contrast: .standard)
    }

    var description: String { rawValue }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        components(
            scheme: environment.colorScheme,
            contrast: environment.colorSchemeContrast
        ).resolve()
    }

    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        let resolved = resolve(in: environment)
        switch self {
        case .white, .black, .clear:
            return Color.ResolvedHDR(resolved)
        default:
            return Color.ResolvedHDR(resolved, headroom: 1)
        }
    }

    private func components(
        scheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> ColorComponents {
        let rgba: (Double, Double, Double, Double)
        switch (self, scheme, contrast) {
        case (.primary, .light, .standard): rgba = (0, 0, 0, 216)
        case (.primary, .dark, .standard): rgba = (255, 255, 255, 216)
        case (.secondary, .light, .standard): rgba = (0, 0, 0, 127)
        case (.secondary, .dark, .standard): rgba = (255, 255, 255, 140)
        case (.primary, .light, .increased): rgba = (0, 0, 0, 255)
        case (.primary, .dark, .increased): rgba = (255, 255, 255, 255)
        case (.secondary, .light, .increased): rgba = (0, 0, 0, 193)
        case (.secondary, .dark, .increased): rgba = (255, 255, 255, 178)

        case (.red, .light, .standard): rgba = (255, 56, 60, 255)
        case (.red, .dark, .standard): rgba = (255, 66, 69, 255)
        case (.orange, .light, .standard): rgba = (255, 141, 40, 255)
        case (.orange, .dark, .standard): rgba = (255, 146, 48, 255)
        case (.yellow, .light, .standard): rgba = (255, 204, 0, 255)
        case (.yellow, .dark, .standard): rgba = (255, 214, 0, 255)
        case (.green, .light, .standard): rgba = (52, 199, 89, 255)
        case (.green, .dark, .standard): rgba = (48, 209, 88, 255)
        case (.mint, .light, .standard): rgba = (0, 200, 179, 255)
        case (.mint, .dark, .standard): rgba = (0, 218, 195, 255)
        case (.teal, .light, .standard): rgba = (0, 195, 208, 255)
        case (.teal, .dark, .standard): rgba = (0, 210, 224, 255)
        case (.cyan, .light, .standard): rgba = (0, 192, 232, 255)
        case (.cyan, .dark, .standard): rgba = (60, 211, 254, 255)
        case (.blue, .light, .standard): rgba = (0, 136, 255, 255)
        case (.blue, .dark, .standard): rgba = (0, 145, 255, 255)
        case (.indigo, .light, .standard): rgba = (97, 85, 245, 255)
        case (.indigo, .dark, .standard): rgba = (109, 124, 255, 255)
        case (.purple, .light, .standard): rgba = (203, 48, 224, 255)
        case (.purple, .dark, .standard): rgba = (219, 52, 242, 255)
        case (.pink, .light, .standard): rgba = (255, 45, 85, 255)
        case (.pink, .dark, .standard): rgba = (255, 55, 95, 255)
        case (.brown, .light, .standard): rgba = (172, 127, 94, 255)
        case (.brown, .dark, .standard): rgba = (183, 138, 102, 255)
        case (.gray, .light, .standard): rgba = (142, 142, 147, 255)
        case (.gray, .dark, .standard): rgba = (152, 152, 157, 255)

        case (.red, .light, .increased): rgba = (233, 21, 45, 255)
        case (.red, .dark, .increased): rgba = (255, 97, 101, 255)
        case (.orange, .light, .increased): rgba = (197, 83, 0, 255)
        case (.orange, .dark, .increased): rgba = (255, 160, 86, 255)
        case (.yellow, .light, .increased): rgba = (161, 106, 0, 255)
        case (.yellow, .dark, .increased): rgba = (254, 223, 67, 255)
        case (.green, .light, .increased): rgba = (0, 137, 50, 255)
        case (.green, .dark, .increased): rgba = (74, 217, 104, 255)
        case (.mint, .light, .increased): rgba = (0, 133, 117, 255)
        case (.mint, .dark, .increased): rgba = (84, 223, 203, 255)
        case (.teal, .light, .increased): rgba = (0, 129, 152, 255)
        case (.teal, .dark, .increased): rgba = (59, 221, 236, 255)
        case (.cyan, .light, .increased): rgba = (0, 126, 174, 255)
        case (.cyan, .dark, .increased): rgba = (109, 217, 255, 255)
        case (.blue, .light, .increased): rgba = (30, 110, 244, 255)
        case (.blue, .dark, .increased): rgba = (92, 184, 255, 255)
        case (.indigo, .light, .increased): rgba = (86, 74, 222, 255)
        case (.indigo, .dark, .increased): rgba = (167, 170, 255, 255)
        case (.purple, .light, .increased): rgba = (176, 47, 194, 255)
        case (.purple, .dark, .increased): rgba = (234, 141, 255, 255)
        case (.pink, .light, .increased): rgba = (231, 18, 77, 255)
        case (.pink, .dark, .increased): rgba = (255, 138, 196, 255)
        case (.brown, .light, .increased): rgba = (149, 109, 81, 255)
        case (.brown, .dark, .increased): rgba = (219, 166, 121, 255)
        case (.gray, .light, .increased): rgba = (105, 105, 110, 255)
        case (.gray, .dark, .increased): rgba = (152, 152, 157, 255)

        case (.white, _, _): rgba = (255, 255, 255, 255)
        case (.black, _, _): rgba = (0, 0, 0, 255)
        case (.clear, _, _): rgba = (0, 0, 0, 0)
        }
        return ColorComponents(
            colorSpace: .sRGB,
            red: rgba.0 / 255,
            green: rgba.1 / 255,
            blue: rgba.2 / 255,
            alpha: rgba.3 / 255
        )
    }
}

final class AnyColorBox: Hashable, @unchecked Sendable {
    static func == (lhs: AnyColorBox, rhs: AnyColorBox) -> Bool {
        lhs.colorProvider.isEqual(to: rhs.colorProvider)
    }

    func hash(into: inout Hasher) {
        self.colorProvider.hash(into: &into)
    }

    private let colorProvider: any ColorProvider

    fileprivate init(_ colorProvider: any ColorProvider) {
        self.colorProvider = colorProvider
    }

    fileprivate var components: ColorComponents { colorProvider.components }
    var colorSpace: Color.RGBColorSpace { components.colorSpace }
    var red: Double { components.red }
    var green: Double { components.green }
    var blue: Double { components.blue }
    var alpha: Double { components.alpha }
    var description: String { colorProvider.description }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        colorProvider.resolve(in: environment)
    }

    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        colorProvider.resolveHDR(in: environment)
    }
}

public struct Color: Hashable, Sendable, CustomStringConvertible {
    public enum RGBColorSpace: Equatable, Hashable, Sendable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

    let provider: AnyColorBox
    public var description: String { provider.description }

    var backendColor: BackendColor {
        backendColor(in: EnvironmentValues())
    }

    func backendColor(in environment: EnvironmentValues) -> BackendColor {
        let resolved = resolve(in: environment)
        return BackendColor(
            Double(resolved.red),
            Double(resolved.green),
            Double(resolved.blue),
            Double(resolved.opacity)
        )
    }

    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        let colorProvider = RGBColorProvider(components: ColorComponents(
            colorSpace: colorSpace,
            red: red,
            green: green,
            blue: blue,
            alpha: opacity
        ))
        self.provider = AnyColorBox(colorProvider)
    }

    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        let colorProvider = RGBColorProvider(components: ColorComponents(
            colorSpace: colorSpace,
            red: white,
            green: white,
            blue: white,
            alpha: opacity
        ))
        self.provider = AnyColorBox(colorProvider)
    }

    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        let sectorValue = hue == 1 ? 0 : hue * 6
        let sector = Int(sectorValue)
        let fraction = sectorValue - Double(sector)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        let r, g, b: Double
        switch sector {
        case 0: (r, g, b) = (brightness, t, p)
        case 1: (r, g, b) = (q, brightness, p)
        case 2: (r, g, b) = (p, brightness, t)
        case 3: (r, g, b) = (p, q, brightness)
        case 4: (r, g, b) = (t, p, brightness)
        default: (r, g, b) = (brightness, p, q)
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    public func opacity(_ opacity: Double) -> Color {
        Color(AnyColorBox(OpacityColor(base: self, opacity: opacity)))
    }

    init(_ provider: AnyColorBox) {
        self.provider = provider
    }

    static func lerp(_ lhs: Self, _ rhs: Self, _ t: CGFloat) -> Self {
        let environment = EnvironmentValues()
        let lhs = lhs.resolve(in: environment)
        let rhs = rhs.resolve(in: environment)
        return Self(
            .sRGBLinear,
            red: VVD.lerp(Double(lhs.linearRed), Double(rhs.linearRed), t),
            green: VVD.lerp(Double(lhs.linearGreen), Double(rhs.linearGreen), t),
            blue: VVD.lerp(Double(lhs.linearBlue), Double(rhs.linearBlue), t),
            opacity: VVD.lerp(Double(lhs.opacity), Double(rhs.opacity), t)
        )
    }
}

extension Color {
    private init(systemColor: SystemColorType) {
        self.init(AnyColorBox(systemColor))
    }

    public static let red = Color(systemColor: .red)
    public static let orange = Color(systemColor: .orange)
    public static let yellow = Color(systemColor: .yellow)
    public static let green = Color(systemColor: .green)
    public static let mint = Color(systemColor: .mint)
    public static let teal = Color(systemColor: .teal)
    public static let cyan = Color(systemColor: .cyan)
    public static let blue = Color(systemColor: .blue)
    public static let indigo = Color(systemColor: .indigo)
    public static let purple = Color(systemColor: .purple)
    public static let pink = Color(systemColor: .pink)
    public static let brown = Color(systemColor: .brown)
    public static let white = Color(systemColor: .white)
    public static let gray = Color(systemColor: .gray)
    public static let black = Color(systemColor: .black)
    public static let clear = Color(systemColor: .clear)
    public static let primary = Color(systemColor: .primary)
    public static let secondary = Color(systemColor: .secondary)
}

extension Color {
    public init(_ resolved: Color.Resolved) {
        self.init(.sRGBLinear,
                  red: Double(resolved.linearRed),
                  green: Double(resolved.linearGreen),
                  blue: Double(resolved.linearBlue),
                  opacity: Double(resolved.opacity))
    }
}

extension Color: ShapeStyle {
    public func resolve(in environment: EnvironmentValues) -> Resolved {
        provider.resolve(in: environment)
    }

    public func resolveHDR(in environment: EnvironmentValues) -> ResolvedHDR {
        provider.resolveHDR(in: environment)
    }
    
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        shape.shading = .color(self)
    }
    
    // Stored in linear light; red/green/blue are computed sRGB accessors.
    public struct Resolved: Hashable, Animatable, ShapeStyle, CustomStringConvertible, Codable {
        public var linearRed:   Float
        public var linearGreen: Float
        public var linearBlue:  Float
        public var opacity:     Float
        
        public init(colorSpace: Color.RGBColorSpace = .sRGB,
                    red: Float, green: Float, blue: Float, opacity: Float = 1) {
            switch colorSpace {
            case .sRGB:
                self.linearRed = Self.sRGBToLinear(red)
                self.linearGreen = Self.sRGBToLinear(green)
                self.linearBlue = Self.sRGBToLinear(blue)
            case .sRGBLinear:
                self.linearRed = red
                self.linearGreen = green
                self.linearBlue = blue
            case .displayP3:
                let red = Self.sRGBToLinear(red)
                let green = Self.sRGBToLinear(green)
                let blue = Self.sRGBToLinear(blue)
                self.linearRed = 1.2249 * red - 0.2247 * green
                self.linearGreen = -0.0420 * red + 1.0419 * green
                self.linearBlue = -0.0197 * red - 0.0786 * green + 1.0979 * blue
            }
            self.opacity = opacity
        }
        
        // sRGB (gamma-encoded) ↔ linear light conversion
        private static func sRGBToLinear(_ c: Float) -> Float {
            let magnitude = abs(c)
            let result = magnitude <= 0.04045
                ? magnitude / 12.92
                : pow((magnitude + 0.055) / 1.055, 2.4)
            return c.sign == .minus ? -result : result
        }
        private static func linearToSRGB(_ c: Float) -> Float {
            let magnitude = abs(c)
            let result = magnitude <= 0.0031308
                ? magnitude * 12.92
                : 1.055 * pow(magnitude, 1.0 / 2.4) - 0.055
            return c.sign == .minus ? -result : result
        }
        
        // Computed sRGB accessors.
        public var red: Float {
            get { Self.linearToSRGB(linearRed) }
            set { linearRed = Self.sRGBToLinear(newValue) }
        }
        public var green: Float {
            get { Self.linearToSRGB(linearGreen) }
            set { linearGreen = Self.sRGBToLinear(newValue) }
        }
        public var blue: Float {
            get { Self.linearToSRGB(linearBlue) }
            set { linearBlue = Self.sRGBToLinear(newValue) }
        }
        
        public typealias AnimatableData = AnimatablePair<Float, AnimatablePair<Float, AnimatablePair<Float, Float>>>
        public var animatableData: AnimatableData {
            get { Self.interpolatableColor(from: self) }
            set { self = Self.resolvedColor(from: newValue) }
        }

        fileprivate static func interpolatableColor(
            from color: Self
        ) -> AnimatableData {
            let l = signedCubeRoot(
                0.4122214708 * color.linearRed +
                    0.5363325363 * color.linearGreen +
                    0.0514459929 * color.linearBlue
            )
            let m = signedCubeRoot(
                0.2119034982 * color.linearRed +
                    0.6806995451 * color.linearGreen +
                    0.1073969566 * color.linearBlue
            )
            let s = signedCubeRoot(
                0.0883024619 * color.linearRed +
                    0.2817188376 * color.linearGreen +
                    0.6299787005 * color.linearBlue
            )
            let scale = color.opacity * 128
            return AnimatableData(
                l * scale,
                .init(
                    m * scale,
                    .init(s * scale, color.opacity * 128)
                )
            )
        }

        fileprivate static func resolvedColor(
            from data: AnimatableData
        ) -> Self {
            let inverseScale: Float = 1 / 128
            var l = data.first * inverseScale
            var m = data.second.first * inverseScale
            var s = data.second.second.first * inverseScale
            let opacity = data.second.second.second * inverseScale
            if opacity != 0 {
                l /= opacity
                m /= opacity
                s /= opacity
            }
            l *= l * l
            m *= m * m
            s *= s * s
            return Self(
                colorSpace: .sRGBLinear,
                red: 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                green: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                blue: -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
                opacity: opacity
            )
        }

        private static func signedCubeRoot(_ value: Float) -> Float {
            let result = pow(abs(value), 1.0 / 3.0)
            return value.sign == .minus ? -result : result
        }
        
        public var description: String {
            String(
                format: "#%02X%02X%02X%02X",
                Self.descriptionComponent(red),
                Self.descriptionComponent(green),
                Self.descriptionComponent(blue),
                Self.descriptionComponent(opacity)
            )
        }

        private static func descriptionComponent(_ value: Float) -> Int32 {
            Int32(value * 255 + 0.5)
        }
        
        public typealias Resolved = Never
        
        public func _apply(to shape: inout _ShapeStyle_Shape) {
            shape.shading = .color(.sRGB,
                                   red: Double(red),
                                   green: Double(green),
                                   blue: Double(blue),
                                   opacity: Double(opacity))
        }
        public static func _apply(to type: inout _ShapeStyle_ShapeType) {}
    }
}

extension Color {
    public struct ResolvedHDR: Hashable, Sendable, Animatable, ShapeStyle, CustomStringConvertible, Codable {
        var base: Color.Resolved
        var _headroom: Float

        public init(_ color: Color.Resolved, headroom: Float? = nil) {
            self.base = color
            self._headroom = headroom ?? .nan
        }

        public var linearRed: Float {
            get { base.linearRed }
            set { base.linearRed = newValue }
        }

        public var linearGreen: Float {
            get { base.linearGreen }
            set { base.linearGreen = newValue }
        }

        public var linearBlue: Float {
            get { base.linearBlue }
            set { base.linearBlue = newValue }
        }

        public var red: Float {
            get { base.red }
            set { base.red = newValue }
        }

        public var green: Float {
            get { base.green }
            set { base.green = newValue }
        }

        public var blue: Float {
            get { base.blue }
            set { base.blue = newValue }
        }

        public var opacity: Float {
            get { base.opacity }
            set { base.opacity = newValue }
        }

        public var headroom: Float? {
            get { _headroom.isNaN ? nil : _headroom }
            set { _headroom = newValue ?? .nan }
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.base == rhs.base && lhs.headroom == rhs.headroom
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(base)
            hasher.combine(headroom)
        }

        public struct _Animatable: VectorArithmetic, Sendable {
            var color: Color.Resolved.AnimatableData
            var headroom: Float

            public static var zero: Self {
                Self(color: .zero, headroom: 0)
            }

            public static func += (lhs: inout Self, rhs: Self) {
                lhs.color += rhs.color
                if lhs.headroom <= rhs.headroom {
                    lhs.headroom = rhs.headroom
                }
            }

            public static func -= (lhs: inout Self, rhs: Self) {
                lhs.color -= rhs.color
                if lhs.headroom <= rhs.headroom {
                    lhs.headroom = rhs.headroom
                }
            }

            public static func + (lhs: Self, rhs: Self) -> Self {
                var result = lhs
                result += rhs
                return result
            }

            public static func - (lhs: Self, rhs: Self) -> Self {
                var result = lhs
                result -= rhs
                return result
            }

            public mutating func scale(by rhs: Double) {
                color.scale(by: rhs)
            }

            public var magnitudeSquared: Double {
                color.magnitudeSquared
            }
        }

        public typealias AnimatableData = _Animatable

        public var animatableData: AnimatableData {
            get {
                AnimatableData(
                    color: base.animatableData,
                    headroom: _headroom.isNaN ? 0 : _headroom
                )
            }
            set {
                base.animatableData = newValue.color
                _headroom = newValue.headroom > 0
                    ? newValue.headroom
                    : .nan
            }
        }

        public var description: String {
            if let headroom {
                return "\(base.description)^\(headroom)"
            }
            return base.description
        }

        public typealias Resolved = Never

        public func _apply(to shape: inout _ShapeStyle_Shape) {
            base._apply(to: &shape)
        }

        public static func _apply(to type: inout _ShapeStyle_ShapeType) {
            Color.Resolved._apply(to: &type)
        }

        private enum CodingKeys: String, CodingKey {
            case color
            case headroom
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let components = try container.decode([Float].self, forKey: .color)
            guard components.count == 4 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .color,
                    in: container,
                    debugDescription: "Expected four resolved color components."
                )
            }
            self.base = Color.Resolved(
                colorSpace: .sRGB,
                red: components[0],
                green: components[1],
                blue: components[2],
                opacity: components[3]
            )
            self._headroom = try container.decodeIfPresent(Float.self, forKey: .headroom) ?? .nan
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode([red, green, blue, opacity], forKey: .color)
            try container.encodeIfPresent(headroom, forKey: .headroom)
        }
    }

    public init(_ resolved: Color.ResolvedHDR) {
        self.init(AnyColorBox(ResolvedHDRColorProvider(color: resolved)))
    }
}

struct ColorView: Equatable, Animatable {
    var color: Color.ResolvedHDR
    var isAntialiased: Bool
    var allowedDynamicRange: Image.DynamicRange

    init(
        _ color: Color.ResolvedHDR,
        isAntialiased: Bool = true,
        allowedDynamicRange: Image.DynamicRange = .standard
    ) {
        self.color = color
        self.isAntialiased = isAntialiased
        self.allowedDynamicRange = allowedDynamicRange
    }

    var animatableData: Color.ResolvedHDR._Animatable {
        get { color.animatableData }
        set { color.animatableData = newValue }
    }

    var contentHeadroom: Float {
        color.headroom ?? 1
    }

    var isClear: Bool {
        color.opacity <= 0
    }

    var isOpaque: Bool {
        color.opacity >= 1
    }
}

extension ColorView: RendererLeafView {
    func contains(
        points: UnsafeBufferPointer<CGPoint>,
        size: CGSize
    ) -> BitVector64 {
        guard color.opacity > 0 else { return [] }
        var result = BitVector64()
        for (index, point) in points.prefix(64).enumerated() {
            result[index] = point.x >= 0 && point.y >= 0 &&
                point.x < size.width && point.y < size.height
        }
        return result
    }

    func content() -> DisplayList.Content.Value {
        .color(self)
    }

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        var animatedView = view
        Self._makeAnimatable(value: &animatedView, inputs: inputs.base)
        return makeLeafView(view: animatedView, inputs: inputs)
    }
}

extension Color: View {
    public typealias Body = Never
}

extension Color: EnvironmentalView {
    func body(environment: EnvironmentValues) -> ColorView {
        let color = resolveHDR(in: environment)
        let dynamicRange: Image.DynamicRange = (color.headroom ?? 1) > 1
            ? .high
            : .standard
        return ColorView(
            color,
            isAntialiased: true,
            allowedDynamicRange: dynamicRange
        )
    }
}
