//
//  File: Color.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

protocol ColorBox: Hashable {
    var colorSpace: Color.RGBColorSpace { get }
    var red: Double     { get set }
    var green: Double   { get set }
    var blue: Double    { get set }
    var alpha: Double   { get set }

    func copy() -> Self
}

struct LinearColor: ColorBox {
    var colorSpace: Color.RGBColorSpace
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    func copy() -> Self {
        Self(colorSpace: colorSpace, red: red, green: green, blue: blue, alpha: alpha)
    }
}

class AnyColorBox: ColorBox, @unchecked Sendable {
    static func == (lhs: AnyColorBox, rhs: AnyColorBox) -> Bool {
        return type(of: lhs.colorBox) == type(of: rhs.colorBox) &&
        lhs.colorBox.colorSpace == rhs.colorBox.colorSpace &&
        lhs.colorBox.red == rhs.colorBox.red &&
        lhs.colorBox.green == rhs.colorBox.green &&
        lhs.colorBox.blue == rhs.colorBox.blue &&
        lhs.colorBox.alpha == rhs.colorBox.alpha
    }
    
    func hash(into: inout Hasher) {
        self.colorBox.hash(into: &into)
    }

    var colorBox: any ColorBox

    required init(_ colorBox: any ColorBox) {
        self.colorBox = colorBox
    }

    var colorSpace: Color.RGBColorSpace { colorBox.colorSpace }
    var red: Double {
        get { colorBox.red }
        set(r) { colorBox.red = r }
    }
    var green: Double {
        get { colorBox.green }
        set(g) { colorBox.green = g }
    }
    var blue: Double {
        get { colorBox.blue }
        set(b) { colorBox.blue = b }
    }
    var alpha: Double {
        get { colorBox.alpha }
        set(a) { colorBox.alpha = a}
    }

    func copy() -> Self {
        Self(self.colorBox.copy())
    }

    var backendColor: VVD.Color {
        switch colorSpace {
        case .sRGBLinear:
            .init(Self.linearToSRGB(red),
                  Self.linearToSRGB(green),
                  Self.linearToSRGB(blue),
                  alpha)
        case .sRGB, .displayP3:
            .init(red, green, blue, alpha)
        }
    }

    private static func linearToSRGB(_ component: Double) -> Double {
        component <= 0.0031308
            ? component * 12.92
            : 1.055 * pow(component, 1.0 / 2.4) - 0.055
    }
}

public struct Color: Hashable, Sendable {
    public enum RGBColorSpace: Equatable, Hashable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

    let provider: AnyColorBox
    var backendColor: VVD.Color { provider.backendColor }

    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        let colorBox = LinearColor(colorSpace: colorSpace,
                                   red: red,
                                   green: green,
                                   blue: blue,
                                   alpha: opacity)
        self.provider = AnyColorBox(colorBox)
    }

    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        let colorBox = LinearColor(colorSpace: colorSpace,
                                   red: white,
                                   green: white,
                                   blue: white,
                                   alpha: opacity)
        self.provider = AnyColorBox(colorBox)
    }

    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        let hue = hue.clamp(min: 0.0, max: 1.0)
        let saturation = saturation.clamp(min: 0.0, max: 1.0)
        let brightness = brightness.clamp(min: 0.0, max: 1.0)

        let c = saturation * brightness
        let h = Int(hue * 360) / 6
        let x = ((h % 2) == 0) ? 0: c
        let m = brightness - c

        let r, g, b: Double
        switch h {
        case 1:     (r, g, b) = (x, c, 0)
        case 2:     (r, g, b) = (0, c, x)
        case 3:     (r, g, b) = (0, x, c)
        case 4:     (r, g, b) = (x, 0, c)
        case 5:     (r, g, b) = (c, 0, x)
        default: // 0, 6
            (r, g, b) = (c, x, 0)
        }

        let red = r + m
        let green = g + m
        let blue = b + m

        let colorBox = LinearColor(colorSpace: .sRGB,
                                   red: red,
                                   green: green,
                                   blue: blue,
                                   alpha: opacity)
        self.provider = AnyColorBox(colorBox)
    }

    public func opacity(_ opacity: Double) -> Color {
        let provider = self.provider.copy()
        provider.alpha = opacity
        return .init(provider)
    }

    init(_ provider: AnyColorBox) {
        self.provider = provider
    }

    static func lerp(_ lhs: Self, _ rhs: Self, _ t: CGFloat) -> Self {
        // FIXME: Convert RGB values to the correct color space.
        let r = VVD.lerp(lhs.provider.red, rhs.provider.red, t)
        let g = VVD.lerp(lhs.provider.green, rhs.provider.green, t)
        let b = VVD.lerp(lhs.provider.blue, rhs.provider.blue, t)
        let a = VVD.lerp(lhs.provider.alpha, rhs.provider.alpha, t)
        return Self(.sRGB, red: r, green: g, blue: b, opacity: a)
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
        Resolved(colorSpace: provider.colorSpace,
                 red: Float(provider.red),
                 green: Float(provider.green),
                 blue: Float(provider.blue),
                 opacity: Float(provider.alpha))
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
            case .sRGBLinear:
                self.linearRed   = red
                self.linearGreen = green
                self.linearBlue  = blue
            default:  // .sRGB, .displayP3: approximate with sRGB gamma
                self.linearRed   = Self.sRGBToLinear(red)
                self.linearGreen = Self.sRGBToLinear(green)
                self.linearBlue  = Self.sRGBToLinear(blue)
            }
            self.opacity = opacity
        }
        
        // sRGB (gamma-encoded) ↔ linear light conversion
        private static func sRGBToLinear(_ c: Float) -> Float {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        private static func linearToSRGB(_ c: Float) -> Float {
            c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
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
        
        // Animatable data follows the stored linear channel order plus opacity.
        public typealias AnimatableData = AnimatablePair<Float, AnimatablePair<Float, AnimatablePair<Float, Float>>>
        public var animatableData: AnimatableData {
            get { .init(linearRed, .init(linearGreen, .init(linearBlue, opacity))) }
            set {
                linearRed   = newValue.first
                linearGreen = newValue.second.first
                linearBlue  = newValue.second.second.first
                opacity     = newValue.second.second.second
            }
        }
        
        public var description: String {
            "Color.Resolved(red: \(red), green: \(green), blue: \(blue), opacity: \(opacity))"
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
            var red: Float
            var green: Float
            var blue: Float
            var opacity: Float

            public static var zero: Self {
                Self(red: 0, green: 0, blue: 0, opacity: 0)
            }

            public static func += (lhs: inout Self, rhs: Self) {
                lhs.red += rhs.red
                lhs.green += rhs.green
                lhs.blue += rhs.blue
                lhs.opacity += rhs.opacity
            }

            public static func -= (lhs: inout Self, rhs: Self) {
                lhs.red -= rhs.red
                lhs.green -= rhs.green
                lhs.blue -= rhs.blue
                lhs.opacity -= rhs.opacity
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
                red.scale(by: rhs)
                green.scale(by: rhs)
                blue.scale(by: rhs)
                opacity.scale(by: rhs)
            }

            public var magnitudeSquared: Double {
                red.magnitudeSquared + green.magnitudeSquared +
                    blue.magnitudeSquared + opacity.magnitudeSquared
            }
        }

        public typealias AnimatableData = _Animatable

        public var animatableData: AnimatableData {
            get {
                AnimatableData(
                    red: linearRed,
                    green: linearGreen,
                    blue: linearBlue,
                    opacity: opacity
                )
            }
            set {
                linearRed = newValue.red
                linearGreen = newValue.green
                linearBlue = newValue.blue
                opacity = newValue.opacity
            }
        }

        public var description: String {
            let value = String(
                format: "#%02X%02X%02X%02X",
                Self.descriptionByte(red),
                Self.descriptionByte(green),
                Self.descriptionByte(blue),
                Self.descriptionByte(opacity)
            )
            if let headroom {
                return "\(value)^\(headroom)"
            }
            return value
        }

        private static func descriptionByte(_ component: Float) -> UInt8 {
            UInt8((component.clamp(min: 0, max: 1) * 255).rounded())
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
        self.init(resolved.base)
    }
}

extension Color: View {
    public typealias Body = Never
}

extension Color: PrimitiveView, UnaryView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer(
                sizeThatFits: { proposal in
                    CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
                }
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(lcAttr))
    }
}
