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

struct ColorComponents: Hashable, Sendable {
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

protocol ColorProvider: Hashable, Serializable {
    var tag: Color.ProviderTag { get }
    func resolve(in environment: EnvironmentValues) -> Color.Resolved
    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR
    func apply(color: Color, to shape: inout _ShapeStyle_Shape)
    var colorDescription: String { get }
    func opacity(at level: Int, environment: EnvironmentValues) -> Float
}

extension ColorProvider {
    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        Color.ResolvedHDR(resolve(in: environment))
    }

    var colorDescription: String { String(describing: self) }

    func apply(color: Color, to shape: inout _ShapeStyle_Shape) {
        _apply(color: color, to: &shape)
    }

    func _apply(color: Color, to shape: inout _ShapeStyle_Shape) {
        switch shape.operation {
        case let .prepareText(level):
            shape.result = .preparedText(.foregroundColor(
                shape.applyingOpacity(at: level, to: color)
            ))
        case let .resolveStyle(name, levels):
            guard !levels.isEmpty else { return }
            var resolved = resolveHDR(in: shape.environment)
            resolved.opacity *= opacity(at: levels.lowerBound, environment: shape.environment)
            shape.storeStyle(.init(.color(resolved)), name: name, level: levels.lowerBound)
        case let .fallbackColor(level):
            shape.result = .color(shape.applyingOpacity(at: level, to: color))
        case .copyStyle, .modifyBackground, .multiLevel, .primaryStyle:
            break
        }
    }

    func opacity(at level: Int, environment: EnvironmentValues) -> Float {
        // Hierarchy opacity belongs to the environment's color definition.
        // This keeps custom color providers and resolved colors on one policy.
        environment.systemColorDefinition.base.opacity(
            at: level,
            environment: environment
        )
    }

}

extension Color {
    struct OpacityColor: ColorProvider, CodableByProxy {
        var base: Color
        var opacity: Double

        var tag: ProviderTag { .opacity }
        var colorDescription: String {
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

        var codingProxy: OpacityDefinition<Double> {
            .init(base: base, opacity: opacity)
        }

        static func unwrap(codingProxy: OpacityDefinition<Double>) -> Self {
            .init(base: codingProxy.base, opacity: codingProxy.opacity)
        }
    }

    struct DisplayP3: ColorProvider, CodableByProxy {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let opacity: Float

        var tag: ProviderTag { .p3 }

        func resolve(in environment: EnvironmentValues) -> Resolved {
            .init(colorSpace: .displayP3, red: Float(red), green: Float(green),
                  blue: Float(blue), opacity: opacity)
        }

        var codingProxy: RGBADefinition<CGFloat, Float> {
            .init(red: red, green: green, blue: blue, opacity: opacity)
        }

        static func unwrap(codingProxy: RGBADefinition<CGFloat, Float>) -> Self {
            .init(red: codingProxy.red, green: codingProxy.green,
                  blue: codingProxy.blue, opacity: codingProxy.opacity)
        }
    }

    struct OpacityDefinition<T: Codable>: Codable {
        @ProxyCodable var base: Color
        var opacity: T
    }
}

struct ResolvedColorProvider: ColorProvider, CodableByProxy {
    var color: Color.ResolvedHDR

    var tag: Color.ProviderTag { .constant }

    var colorDescription: String {
        if color.headroom == nil {
            if color.linearRed == 0,
               color.linearGreen == 0,
               color.linearBlue == 0 {
                if color.opacity == 0 {
                    return "clear"
                }
                if color.opacity == 1 {
                    return "black"
                }
            } else if color.linearRed == 1,
                      color.linearGreen == 1,
                      color.linearBlue == 1,
                      color.opacity == 1 {
                return "white"
            }
        }
        return color.description
    }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        color.base
    }

    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        color
    }

    var codingProxy: Color.RGBADefinition<Float, Float> { color.base.codingProxy }

    static func unwrap(codingProxy: Color.RGBADefinition<Float, Float>) -> Self {
        .init(color: .init(Color.Resolved.unwrap(codingProxy: codingProxy)))
    }
}

enum SystemColorType: ColorProvider, CodableSerializable, Sendable {
    case red, orange, yellow, green, teal, mint, cyan, blue
    case indigo, purple, pink, brown, gray
    case primary, secondary, tertiary, quaternary, quinary
    case primaryFill, secondaryFill, tertiaryFill, quaternaryFill

    var tag: Color.ProviderTag { .system }
    var colorDescription: String { description }

    var description: String {
        switch self {
        case .red: "red"
        case .orange: "orange"
        case .yellow: "yellow"
        case .green: "green"
        case .teal: "teal"
        case .mint: "mint"
        case .cyan: "cyan"
        case .blue: "blue"
        case .indigo: "indigo"
        case .purple: "purple"
        case .pink: "pink"
        case .brown: "brown"
        case .gray: "gray"
        case .primary: "primary"
        case .secondary: "secondary"
        case .tertiary: "tertiary"
        case .quaternary: "quaternary"
        case .quinary: "quinary"
        case .primaryFill: "primaryFill"
        case .secondaryFill: "secondaryFill"
        case .tertiaryFill: "tertiaryFill"
        case .quaternaryFill: "quaternaryFill"
        }
    }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        resolveHDR(in: environment).base
    }

    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        environment.systemColorDefinition.base.value(
            for: self,
            environment: environment
        )
    }

    fileprivate func components(
        scheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> ColorComponents {
        let rgba: (Double, Double, Double, Double)
        switch (self, scheme, contrast) {
        case (.primary, .light, .standard): rgba = (0, 0, 0, 216)
        case (.primary, .dark, .standard): rgba = (255, 255, 255, 216)
        case (.secondary, .light, .standard): rgba = (0, 0, 0, 127)
        case (.secondary, .dark, .standard): rgba = (255, 255, 255, 140)
        case (.tertiary, .light, .standard): rgba = (0, 0, 0, 66)
        case (.tertiary, .dark, .standard): rgba = (255, 255, 255, 63)
        case (.quaternary, .light, .standard): rgba = (0, 0, 0, 25)
        case (.quaternary, .dark, .standard): rgba = (255, 255, 255, 25)
        case (.quinary, .light, .standard): rgba = (0, 0, 0, 12)
        case (.quinary, .dark, .standard): rgba = (255, 255, 255, 12)
        case (.primary, .light, .increased): rgba = (0, 0, 0, 255)
        case (.primary, .dark, .increased): rgba = (255, 255, 255, 255)
        case (.secondary, .light, .increased): rgba = (0, 0, 0, 193)
        case (.secondary, .dark, .increased): rgba = (255, 255, 255, 178)
        case (.tertiary, .light, .increased): rgba = (0, 0, 0, 142)
        case (.tertiary, .dark, .increased): rgba = (255, 255, 255, 127)
        case (.quaternary, .light, .increased): rgba = (0, 0, 0, 89)
        case (.quaternary, .dark, .increased): rgba = (255, 255, 255, 76)
        case (.quinary, .light, .increased): rgba = (0, 0, 0, 38)
        case (.quinary, .dark, .increased): rgba = (255, 255, 255, 38)

        case (.primaryFill, .light, .standard):
            rgba = (120, 120, 128, 0.20 * 255)
        case (.primaryFill, .dark, .standard):
            rgba = (120, 120, 128, 0.36 * 255)
        case (.primaryFill, .light, .increased):
            rgba = (120, 120, 128, 0.28 * 255)
        case (.primaryFill, .dark, .increased):
            rgba = (120, 120, 128, 0.44 * 255)
        case (.secondaryFill, .light, .standard):
            rgba = (120, 120, 128, 0.16 * 255)
        case (.secondaryFill, .dark, .standard):
            rgba = (120, 120, 128, 0.32 * 255)
        case (.secondaryFill, .light, .increased):
            rgba = (120, 120, 128, 0.24 * 255)
        case (.secondaryFill, .dark, .increased):
            rgba = (120, 120, 128, 0.40 * 255)
        case (.tertiaryFill, .light, .standard):
            rgba = (120, 120, 128, 0.12 * 255)
        case (.tertiaryFill, .dark, .standard):
            rgba = (118, 118, 128, 0.24 * 255)
        case (.tertiaryFill, .light, .increased):
            rgba = (118, 118, 128, 0.20 * 255)
        case (.tertiaryFill, .dark, .increased):
            rgba = (118, 118, 128, 0.32 * 255)
        case (.quaternaryFill, .light, .standard):
            rgba = (116, 116, 128, 0.08 * 255)
        case (.quaternaryFill, .dark, .standard):
            rgba = (116, 116, 128, 0.18 * 255)
        case (.quaternaryFill, .light, .increased):
            rgba = (116, 116, 128, 0.12 * 255)
        case (.quaternaryFill, .dark, .increased):
            rgba = (116, 116, 128, 0.26 * 255)

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

protocol SystemColorDefinition {
    static func value(
        for type: SystemColorType,
        environment: EnvironmentValues
    ) -> Color.ResolvedHDR

    static func opacity(
        at level: Int,
        environment: EnvironmentValues
    ) -> Float
}

extension SystemColorDefinition {
    static func opacity(
        at level: Int,
        environment: EnvironmentValues
    ) -> Float {
        switch level {
        case ...0: 1
        case 1: 0.5
        case 2: 0.25
        default: 0.18
        }
    }
}

struct SystemColorDefinitionType: Equatable, @unchecked Sendable {
    var base: any SystemColorDefinition.Type

    static func == (
        lhs: SystemColorDefinitionType,
        rhs: SystemColorDefinitionType
    ) -> Bool {
        // Definition identity is the concrete metatype. The existential
        // conformance witness is an implementation detail of that metatype.
        ObjectIdentifier(lhs.base) == ObjectIdentifier(rhs.base)
    }
}

private struct DefaultSystemColorDefinition: SystemColorDefinition {
    static func value(
        for type: SystemColorType,
        environment: EnvironmentValues
    ) -> Color.ResolvedHDR {
        // The default definition resolves every semantic color from the same
        // scheme-and-contrast snapshot used by the hierarchy opacity policy.
        Color.ResolvedHDR(
            type.components(
                scheme: environment.colorScheme,
                contrast: environment.colorSchemeContrast
            ).resolve(),
            headroom: 1
        )
    }
}

private struct SystemColorDefinitionKey: EnvironmentKey {
    static let defaultValue = SystemColorDefinitionType(
        base: DefaultSystemColorDefinition.self
    )
}

extension EnvironmentValues {
    var systemColorDefinition: SystemColorDefinitionType {
        get { self[SystemColorDefinitionKey.self] }
        set { self[SystemColorDefinitionKey.self] = newValue }
    }
}

class AnyColorBox: AnyShapeStyleBox, AnyCodableBox, @unchecked Sendable {
    typealias Box = AnyColorBox
    typealias Tag = Color.ProviderTag

    var tag: Tag { fatalError("Abstract color box.") }
    var colorDescription: String { fatalError("Abstract color box.") }

    func hash(into hasher: inout Hasher) { fatalError("Abstract color box.") }
    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        fatalError("Abstract color box.")
    }
    func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        fatalError("Abstract color box.")
    }
    func apply(color: Color, to shape: inout _ShapeStyle_Shape) {
        fatalError("Abstract color box.")
    }
    func opacity(at level: Int, environment: EnvironmentValues) -> Float {
        fatalError("Abstract color box.")
    }

    override func apply(to shape: inout _ShapeStyle_Shape) {
        let color = Color(self)
        if case let .fallbackColor(level) = shape.operation {
            shape.result = .color(shape.applyingOpacity(at: level, to: color))
        } else {
            apply(color: color, to: &shape)
        }
    }

    func `as`<T: ColorProvider>(_ type: T.Type) -> T? {
        (self as? ColorBox<T>)?.base
    }
}

final class ColorBox<T: ColorProvider>: AnyColorBox, CodableBox, @unchecked Sendable {
    let base: T

    init(_ base: T) { self.base = base }

    override var tag: Tag { base.tag }
    override var colorDescription: String { base.colorDescription }
    override func hash(into hasher: inout Hasher) { base.hash(into: &hasher) }
    override func isEqual(to other: AnyShapeStyleBox) -> Bool {
        guard let other = other as? ColorBox<T> else { return false }
        return base == other.base
    }
    override func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        base.resolve(in: environment)
    }
    override func resolveHDR(in environment: EnvironmentValues) -> Color.ResolvedHDR {
        base.resolveHDR(in: environment)
    }
    override func apply(color: Color, to shape: inout _ShapeStyle_Shape) {
        base.apply(color: color, to: &shape)
    }
    override func opacity(at level: Int, environment: EnvironmentValues) -> Float {
        base.opacity(at: level, environment: environment)
    }
    func serialize(to encoder: any Encoder) throws {
        try base.serialize(to: encoder)
    }
    static func deserialize(from decoder: any Decoder) throws -> ColorBox<T> {
        ColorBox(try T.deserialize(from: decoder))
    }
}

public struct Color: Hashable, Sendable, CustomStringConvertible {
    public enum RGBColorSpace: Equatable, Hashable, Sendable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

    var provider: AnyColorBox
    public var description: String { provider.colorDescription }

    public static func == (lhs: Color, rhs: Color) -> Bool {
        lhs.provider === rhs.provider || lhs.provider.isEqual(to: rhs.provider)
    }

    public func hash(into hasher: inout Hasher) { provider.hash(into: &hasher) }

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
        switch colorSpace {
        case .sRGB, .sRGBLinear:
            let resolved = Resolved(colorSpace: colorSpace, red: Float(red),
                                    green: Float(green), blue: Float(blue), opacity: Float(opacity))
            provider = ColorBox(ResolvedColorProvider(color: .init(resolved)))
        case .displayP3:
            provider = ColorBox(DisplayP3(red: CGFloat(red), green: CGFloat(green),
                                          blue: CGFloat(blue), opacity: Float(opacity)))
        }
    }

    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        self.init(colorSpace, red: white, green: white, blue: white, opacity: opacity)
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
        Color(ColorBox(OpacityColor(base: self, opacity: opacity)))
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
    fileprivate init(systemColor: SystemColorType) {
        self.init(ColorBox(systemColor))
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
    public static let white = Color(Color.ResolvedHDR(Color.Resolved(
        colorSpace: .sRGBLinear,
        red: 1,
        green: 1,
        blue: 1
    )))
    public static let gray = Color(systemColor: .gray)
    public static let black = Color(Color.ResolvedHDR(Color.Resolved(
        colorSpace: .sRGBLinear,
        red: 0,
        green: 0,
        blue: 0
    )))
    public static let clear = Color(Color.ResolvedHDR(Color.Resolved(
        colorSpace: .sRGBLinear,
        red: 0,
        green: 0,
        blue: 0,
        opacity: 0
    )))
    public static let primary = Color(systemColor: .primary)
    public static let secondary = Color(systemColor: .secondary)
}

struct SystemColorsStyle: PrimitiveShapeStyle {
    func _apply(to shape: inout _ShapeStyle_Shape) {
        switch shape.operation {
        case let .prepareText(level):
            shape.result = .preparedText(
                .foregroundColor(color(at: level))
            )
        case let .resolveStyle(name, levels):
            shape.result = .pack(_ShapeStyle_Pack(styles: levels.map { level in
                (
                    key: _ShapeStyle_Pack.Key(name, level),
                    style: _ShapeStyle_Pack.Style(
                        .color(color(at: level).resolveHDR(
                            in: shape.environment
                        ))
                    )
                )
            }))
        case let .fallbackColor(level):
            shape.result = .color(color(at: level))
        case .copyStyle, .modifyBackground, .multiLevel, .primaryStyle:
            break
        }
    }

    static func _apply(to type: inout _ShapeStyle_ShapeType) {
    }

    private func color(at level: Int) -> Color {
        switch level {
        case ...0:
            Color(systemColor: .primary)
        case 1:
            Color(systemColor: .secondary)
        case 2:
            Color(systemColor: .tertiary)
        case 3:
            Color(systemColor: .quaternary)
        default:
            Color(systemColor: .quinary)
        }
    }

    typealias Resolved = Never
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
        provider.apply(to: &shape)
    }

    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
    }
    
    // Stored in linear light; red/green/blue are computed sRGB accessors.
    public struct Resolved: Hashable, Animatable, PrimitiveShapeStyle, CustomStringConvertible, Codable {
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
            if magnitude == 1 { return c }
            let result = magnitude <= 0.04045
                ? magnitude / 12.92
                : pow((magnitude + 0.055) / 1.055, 2.4)
            return c.sign == .minus ? -result : result
        }
        private static func linearToSRGB(_ c: Float) -> Float {
            let magnitude = abs(c)
            if magnitude == 1 { return c }
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
            get {
                let color = ResolvedGradient.ColorSpace.perceptual.convertIn(self)
                return AnimatableData(color.r * 128, .init(color.g * 128, .init(color.b * 128, color.a * 128)))
            }
            set {
                let inverseScale: Float = 1 / 128
                self = ResolvedGradient.ColorSpace.perceptual.convertOut(.init(
                    r: newValue.first * inverseScale,
                    g: newValue.second.first * inverseScale,
                    b: newValue.second.second.first * inverseScale,
                    a: newValue.second.second.second * inverseScale
                ))
            }
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
            let resolved: Self
            if case let .fallbackColor(level) = shape.operation {
                resolved = shape.applyingOpacity(at: level, to: self)
            } else {
                resolved = self
            }
            shape.result = .color(Color(resolved))
        }
        public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        }
    }
}

extension Color.Resolved {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(red)
        try container.encode(green)
        try container.encode(blue)
        try container.encode(opacity)
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let red = try container.decode(Float.self)
        let green = try container.decode(Float.self)
        let blue = try container.decode(Float.self)
        let opacity = try container.decode(Float.self)
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension Color {
    struct RGBADefinition<RGB: Codable, Alpha: Codable>: Codable {
        var red: RGB
        var green: RGB
        var blue: RGB
        var opacity: Alpha
    }
}

extension Color.Resolved: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        if linearRed != 0 { encoder.encodeFloatFieldAlways(1, linearRed) }
        if linearGreen != 0 { encoder.encodeFloatFieldAlways(2, linearGreen) }
        if linearBlue != 0 { encoder.encodeFloatFieldAlways(3, linearBlue) }
        if opacity != 1 { encoder.encodeFloatFieldAlways(4, opacity) }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var red: Float = 0
        var green: Float = 0
        var blue: Float = 0
        var opacity: Float = 1
        while let field = try decoder.nextField() {
            switch field.tag {
            case 1: red = try decoder.floatField(field)
            case 2: green = try decoder.floatField(field)
            case 3: blue = try decoder.floatField(field)
            case 4: opacity = try decoder.floatField(field)
            default: try decoder.skipField(field)
            }
        }
        self.init(colorSpace: .sRGBLinear, red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension Color.ResolvedHDR: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) {
        if linearRed != 0 { encoder.encodeFloatFieldAlways(1, linearRed) }
        if linearGreen != 0 { encoder.encodeFloatFieldAlways(2, linearGreen) }
        if linearBlue != 0 { encoder.encodeFloatFieldAlways(3, linearBlue) }
        if opacity != 1 { encoder.encodeFloatFieldAlways(4, opacity) }
        if _headroom != 0 && !_headroom.isNaN {
            encoder.encodeFloatFieldAlways(5, _headroom)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var red: Float = 0
        var green: Float = 0
        var blue: Float = 0
        var opacity: Float = 1
        var headroom: Float = .nan
        while let field = try decoder.nextField() {
            switch field.tag {
            case 1: red = try decoder.floatField(field)
            case 2: green = try decoder.floatField(field)
            case 3: blue = try decoder.floatField(field)
            case 4: opacity = try decoder.floatField(field)
            case 5: headroom = try decoder.floatField(field)
            default: try decoder.skipField(field)
            }
        }
        self.init(
            .init(colorSpace: .sRGBLinear, red: red, green: green, blue: blue, opacity: opacity),
            headroom: headroom
        )
    }
}

extension Color.Resolved: CodableByProxy {
    var codingProxy: Color.RGBADefinition<Float, Float> {
        .init(red: linearRed, green: linearGreen, blue: linearBlue, opacity: opacity)
    }

    static func unwrap(codingProxy: Color.RGBADefinition<Float, Float>) -> Self {
        .init(colorSpace: .sRGBLinear, red: codingProxy.red,
              green: codingProxy.green, blue: codingProxy.blue, opacity: codingProxy.opacity)
    }
}

extension Color {
    public struct ResolvedHDR: Hashable, Sendable, Animatable, PrimitiveShapeStyle, CustomStringConvertible, Codable {
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
        self.init(ColorBox(ResolvedColorProvider(color: resolved)))
    }
}

extension Color: Serializable {
    enum ProviderTag: Codable, CodableBoxTag {
        case constant, p3, system, opacity

        typealias Box = AnyColorBox

        var type: any ColorProvider.Type {
            switch self {
            case .constant: ResolvedColorProvider.self
            case .p3: DisplayP3.self
            case .system: SystemColorType.self
            case .opacity: OpacityColor.self
            }
        }

        var box: any CodableBox<AnyColorBox>.Type {
            func box<T: ColorProvider>(for type: T.Type) -> any CodableBox<AnyColorBox>.Type {
                ColorBox<T>.self
            }
            return _openExistential(type, do: box(for:))
        }
    }

    func serialize(to encoder: any Encoder) throws { try provider.encode(to: encoder) }

    static func deserialize(from decoder: any Decoder) throws -> Color {
        Color(try AnyColorBox.decode(from: decoder))
    }
}

extension Color {
    // Preserve the encoded color representation at the renderer boundary.
    // The provider itself owns only its concrete value and resolution behavior.
    func renderingComponents(in environment: EnvironmentValues = EnvironmentValues()) -> ColorComponents {
        if let p3 = provider.as(DisplayP3.self) {
            return .init(colorSpace: .displayP3, red: Double(p3.red), green: Double(p3.green),
                         blue: Double(p3.blue), alpha: Double(p3.opacity))
        }
        if let wrapper = provider.as(OpacityColor.self) {
            var components = wrapper.base.renderingComponents(in: environment)
            components.alpha *= wrapper.opacity
            return components
        }
        let color = resolve(in: environment)
        return .init(colorSpace: .sRGB, red: Double(color.red), green: Double(color.green),
                     blue: Double(color.blue), alpha: Double(color.opacity))
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
        color.opacity == 0
    }

    var isOpaque: Bool {
        color.opacity == 1
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
