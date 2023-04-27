//
//  File: GraphicsContext+Filter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

extension GraphicsContext {
        public struct Filter {
        enum FilterStyle {
            case transformMatrix(matrix: ProjectionTransform)
            case colorMatrix(matrix: ColorMatrix)
            case blur(radius: CGFloat, options: BlurOptions)
            case shadow(color: Color, radius: CGFloat, offset: CGPoint, blendMode: BlendMode, options: ShadowOptions)
        }
        let style: FilterStyle

        public static func projectionTransform(_ matrix: ProjectionTransform) -> Filter {
            Filter(style: .transformMatrix(matrix: matrix))
        }

        public static func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33),
                                  radius: CGFloat,
                                  x: CGFloat = 0,
                                  y: CGFloat = 0,
                                  blendMode: BlendMode = .normal,
                                  options: ShadowOptions = ShadowOptions()) -> Filter {
            Filter(style: .shadow(color: color,
                                  radius: radius,
                                  offset: CGPoint(x: x, y: y),
                                  blendMode: blendMode,
                                  options: options))
        }

        public static func colorMultiply(_ color: Color) -> Filter {
            let cc = color.dkColor
            var cm = ColorMatrix.identity
            cm.r1 = Float(cc.r)
            cm.g2 = Float(cc.g)
            cm.b3 = Float(cc.b)
            cm.a4 = Float(cc.a)
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func colorMatrix(_ matrix: ColorMatrix) -> Filter {
            Filter(style: .colorMatrix(matrix: matrix))
        }

        public static func hueRotation(_ angle: Angle) -> Filter {
            let c = Float(cos(angle.radians))
            let s = Float(sin(angle.radians))
            var cm = ColorMatrix.identity

            cm.r1 = 0.213 + c * 0.787 - s * 0.213
            cm.r2 = 0.715 - c * 0.715 - s * 0.715
            cm.r3 = 0.072 - c * 0.072 + s * 0.928

            cm.g1 = 0.213 - c * 0.213 + s * 0.143
            cm.g2 = 0.715 + c * 0.285 + s * 0.140
            cm.g3 = 0.072 - c * 0.072 - s * 0.283

            cm.b1 = 0.213 - c * 0.213 - s * 0.787
            cm.b2 = 0.715 - c * 0.715 + s * 0.715
            cm.b3 = 0.072 + c * 0.928 + s * 0.072

            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func saturation(_ amount: Double) -> Filter {
            let s = Float(amount)
            let sr = (1 - s) * 0.213
            let sg = (1 - s) * 0.715
            let sb = (1 - s) * 0.072
            var cm = ColorMatrix.identity
            cm.r1 = sr + s
            cm.r2 = sg
            cm.r3 = sb
            cm.g1 = sr
            cm.g2 = sg + s
            cm.g3 = sb
            cm.b1 = sr
            cm.b2 = sg
            cm.b3 = sb + s
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func brightness(_ amount: Double) -> Filter {
            let b = Float(amount)
            var cm = ColorMatrix.identity
            cm.r5 = b
            cm.g5 = b
            cm.b5 = b
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func contrast(_ amount: Double) -> Filter {
            let c = Float(amount)
            let t = (1 - c) * 0.5
            var cm = ColorMatrix.identity
            cm.r1 = c
            cm.g2 = c
            cm.b3 = c
            cm.r5 = t
            cm.g5 = t
            cm.b5 = t
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func colorInvert(_ amount: Double = 1) -> Filter {
            let c = Float(amount)
            let r = 1.0 - c * 2.0
            var cm = ColorMatrix.identity
            cm.r1 = r
            cm.g2 = r
            cm.b2 = r
            cm.r5 = c
            cm.g5 = c
            cm.b5 = c
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func grayscale(_ amount: Double) -> Filter {
            let a = Float(1 - amount)
            var cm = ColorMatrix.identity
            cm.r1 = 0.213 + 0.787 * a
            cm.r2 = 0.715 - 0.715 * a
            cm.r3 = 0.072 - 0.072 * a
            cm.g1 = 0.213 - 0.213 * a
            cm.g2 = 0.715 + 0.285 * a
            cm.g3 = 0.072 - 0.072 * a
            cm.b1 = 0.213 - 0.213 * a
            cm.b2 = 0.715 - 0.715 * a
            cm.b3 = 0.072 + 0.928 * a
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static var luminanceToAlpha: Filter {
            var cm = ColorMatrix.zero
            cm.a1 = 0.2126
            cm.a2 = 0.7152
            cm.a3 = 0.0722
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func blur(radius: CGFloat,
                                options: BlurOptions = BlurOptions()) -> Filter {
            Filter(style: .blur(radius: radius, options: options))
        }

        public static func alphaThreshold(min: Double,
                                          max: Double = 1,
                                          color: Color = Color.black) -> Filter {
            fatalError()
        }
    }

    public struct ShadowOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var shadowAbove   = ShadowOptions(rawValue: 1)
        public static var shadowOnly    = ShadowOptions(rawValue: 2)
        public static var invertsAlpha  = ShadowOptions(rawValue: 4)
        public static var disablesGroup = ShadowOptions(rawValue: 8)
    }

    public struct BlurOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var opaque        = BlurOptions(rawValue: 1)
        public static var dithersResult = BlurOptions(rawValue: 2)
    }

    public struct FilterOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var linearColor = FilterOptions(rawValue: 1)
    }

    public mutating func addFilter(_ filter: Filter,
                                   options: FilterOptions = FilterOptions()) {
        filters.append((filter, options))
    }
}
