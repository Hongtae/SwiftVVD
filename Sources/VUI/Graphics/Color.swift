//
//  File: Color.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

protocol ColorBox: Hashable {
    var red: Double     { get set }
    var green: Double   { get set }
    var blue: Double    { get set }
    var alpha: Double   { get set }

    func copy() -> Self
}

struct LinearColor: ColorBox {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    func copy() -> Self {
        Self(red: red, green: green, blue: blue, alpha: alpha)
    }
}

class AnyColorBox: ColorBox, @unchecked Sendable {
    static func == (lhs: AnyColorBox, rhs: AnyColorBox) -> Bool {
        return type(of: lhs.colorBox) == type(of: rhs.colorBox) &&
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

    var dkColor: VVD.Color {
        .init(self.red, self.green, self.blue, self.alpha)
    }
}

public struct Color: Hashable {
    public enum RGBColorSpace: Equatable, Hashable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

    let provider: AnyColorBox
    var dkColor: VVD.Color { provider.dkColor }

    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        let colorBox = LinearColor(red: red, green: green, blue: blue, alpha: opacity)
        self.provider = AnyColorBox(colorBox)
    }

    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        let colorBox = LinearColor(red: white, green: white, blue: white, alpha: opacity)
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

        let colorBox = LinearColor(red: red, green: green, blue: blue, alpha: opacity)
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

extension Color: ShapeStyle {
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        shape.shading = .color(self)
    }
}

extension Color: View {
    public typealias Body = Never
}

extension Color: _PrimitiveView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            ColorViewContext(graph: graph, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }
}

private class ColorViewContext: PrimitiveViewContext<Color> {
    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)
        if let color = self.view {
            context.fill(Path(frame), with: .color(color))
        }
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        guard let color = self.view, color.provider.alpha > 0 else {
            return super.hitTest(location)
        }
        if bounds.contains(location) { return self }
        return super.hitTest(location)
    }
}
