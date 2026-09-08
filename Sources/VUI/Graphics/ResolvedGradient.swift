//
//  File: ResolvedGradient.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ResolvedGradient: Equatable, Animatable, Sendable {
    struct Stop: Equatable, Sendable {
        var color: Color.Resolved
        var location: CGFloat
        var interpolation: BezierTimingFunction<Float>?
    }

    enum ColorSpace: UInt8, Hashable, Sendable {
        case device, linear, perceptual

        struct InterpolatableColor: Equatable, Sendable {
            var r: Float
            var g: Float
            var b: Float
            var a: Float
        }

        func convertIn(_ color: Color.Resolved) -> InterpolatableColor {
            var r = color.linearRed
            var g = color.linearGreen
            var b = color.linearBlue
            switch self {
            case .device:
                func encode(_ value: Float) -> Float {
                    let magnitude = value > 0 ? value : -value
                    let result: Float
                    if magnitude <= 0.0031308 {
                        result = magnitude * 12.92
                    } else if magnitude == 1 {
                        result = 1
                    } else {
                        result = pow(magnitude, 1 / 2.4) * 1.055 - 0.055
                    }
                    return value > 0 ? result : -result
                }
                r = encode(r)
                g = encode(g)
                b = encode(b)
            case .linear:
                break
            case .perceptual:
                func cubeRoot(_ value: Float) -> Float {
                    let result = pow(abs(value), 1 / 3)
                    return value.sign == .minus ? -result : result
                }
                let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
                let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
                let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
                r = cubeRoot(l)
                g = cubeRoot(m)
                b = cubeRoot(s)
            }
            return InterpolatableColor(r: r * color.opacity, g: g * color.opacity,
                                       b: b * color.opacity, a: color.opacity)
        }

        func convertOut(_ color: InterpolatableColor) -> Color.Resolved {
            var r = color.r
            var g = color.g
            var b = color.b
            // Zero alpha keeps the supplied components; animated vectors can
            // contain nonzero color even when their alpha cancels to zero.
            if color.a != 0 {
                let inverseAlpha: Float = 1 / color.a
                r *= inverseAlpha
                g *= inverseAlpha
                b *= inverseAlpha
            }
            switch self {
            case .device:
                func decode(_ value: Float) -> Float {
                    let magnitude = value > 0 ? value : -value
                    let result: Float
                    if magnitude <= 0.04045 {
                        result = magnitude * 0.07739938
                    } else if magnitude == 1 {
                        result = 1
                    } else {
                        result = pow(magnitude * 0.9478673338890076 + 0.052132703363895416, 2.4)
                    }
                    return value > 0 ? result : -result
                }
                r = decode(r)
                g = decode(g)
                b = decode(b)
            case .linear:
                break
            case .perceptual:
                let l = r * (r * r)
                let m = g * (g * g)
                let s = b * (b * b)
                r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
                g = 2.6097574011 * m - 1.2684380046 * l - 0.3413193965 * s
                b = 1.7076147010 * s + (-0.0041960863 * l - 0.7034186147 * m)
            }
            return Color.Resolved(colorSpace: .sRGBLinear, red: r, green: g, blue: b, opacity: color.a)
        }
    }

    var stops: [Stop]
    var colorSpace: ColorSpace
    var headroom: Float?

    var animatableData: ResolvedGradientVector {
        get { ResolvedGradientVector(self) }
        set {
            stops.removeAll(keepingCapacity: true)
            stops.reserveCapacity(newValue.stops.count)
            for stop in newValue.stops {
                stops.append(Stop(color: newValue.colorSpace.convertOut(stop.color),
                                  location: stop.location, interpolation: stop.interpolation))
            }
        }
    }
}

struct ResolvedGradientVector: VectorArithmetic, Sendable {
    fileprivate struct Stop: Equatable, Sendable {
        var color: ResolvedGradient.ColorSpace.InterpolatableColor
        var location: CGFloat
        var interpolation: BezierTimingFunction<Float>?
    }

    fileprivate var stops: [Stop]
    var colorSpace: ResolvedGradient.ColorSpace
    var headroom: Float?

    static var zero: Self { Self(stops: [], colorSpace: .device, headroom: nil) }

    static func + (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result += rhs
        return result
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result -= rhs
        return result
    }

    static func += (lhs: inout Self, rhs: Self) { lhs.add(rhs, scaledBy: 1) }
    static func -= (lhs: inout Self, rhs: Self) { lhs.add(rhs, scaledBy: -1) }

    mutating func scale(by rhs: Double) {
        let scale = Float(rhs)
        for index in stops.indices {
            var color = stops[index].color
            color.r *= scale
            color.g *= scale
            color.b *= scale
            color.a *= scale
            stops[index].color = color
        }
    }

    var magnitudeSquared: Double {
        var result: Double = 0
        for stop in stops {
            let color = stop.color
            result += Double(color.r * color.r + color.g * color.g + color.b * color.b + color.a * color.a)
        }
        return result
    }

    mutating func setColorSpace(_ colorSpace: ResolvedGradient.ColorSpace) {
        guard colorSpace != self.colorSpace else { return }
        for index in stops.indices {
            stops[index].color = colorSpace.convertIn(self.colorSpace.convertOut(stops[index].color))
        }
        self.colorSpace = colorSpace
    }

    mutating func add(_ other: Self, scaledBy scale: Double) {
        guard !other.stops.isEmpty else { return }
        let factor = Float(scale)
        if stops.isEmpty {
            if scale == 1 {
                stops = other.stops
            } else {
                stops.reserveCapacity(other.stops.count)
                for stop in other.stops {
                    let color = stop.color
                    stops.append(Stop(color: .init(r: color.r * factor, g: color.g * factor,
                                                   b: color.b * factor, a: color.a * factor),
                                      location: stop.location, interpolation: nil))
                }
            }
            colorSpace = other.colorSpace
            headroom = other.headroom
            return
        }
        setColorSpace(other.colorSpace)
        if stops.count == other.stops.count && zip(stops, other.stops).allSatisfy({ $0.location == $1.location }) {
            for index in stops.indices {
                let otherStop = other.stops[index]
                var stop = stops[index]
                stop.color.r += otherStop.color.r * factor
                stop.color.g += otherStop.color.g * factor
                stop.color.b += otherStop.color.b * factor
                stop.color.a += otherStop.color.a * factor
                if stop.interpolation != nil || otherStop.interpolation != nil {
                    let lhs = stop.interpolation ?? .init(p1x: 0, p1y: 0, p2x: 1, p2y: 1)
                    let rhs = otherStop.interpolation ?? .init(p1x: 0, p1y: 0, p2x: 1, p2y: 1)
                    // Curve arithmetic scales the receiver, unlike color arithmetic.
                    stop.interpolation = .init(p1x: lhs.p1x * factor + rhs.p1x,
                                               p1y: lhs.p1y * factor + rhs.p1y,
                                               p2x: lhs.p2x * factor + rhs.p2x,
                                               p2y: lhs.p2y * factor + rhs.p2y)
                }
                stops[index] = stop
            }
            return
        }

        func sample(_ stops: [Stop], at location: CGFloat, next index: Int) -> ResolvedGradient.ColorSpace.InterpolatableColor {
            if index == 0 { return stops[0].color }
            if index == stops.count { return stops[index - 1].color }
            let previous = stops[index - 1]
            let next = stops[index]
            if previous.location == next.location { return previous.color }
            let amount = Float((location - previous.location) / (next.location - previous.location))
            let inverse: Float = 1 - amount
            return .init(r: previous.color.r * inverse + next.color.r * amount,
                         g: previous.color.g * inverse + next.color.g * amount,
                         b: previous.color.b * inverse + next.color.b * amount,
                         a: previous.color.a * inverse + next.color.a * amount)
        }

        var merged: [Stop] = []
        merged.reserveCapacity(max(stops.count, other.stops.count))
        var lhsIndex = 0
        var rhsIndex = 0
        while lhsIndex < stops.count || rhsIndex < other.stops.count {
            let lhsLocation = lhsIndex < stops.count ? stops[lhsIndex].location : .infinity
            let rhsLocation = rhsIndex < other.stops.count ? other.stops[rhsIndex].location : .infinity
            var stop: Stop
            let rhsColor: ResolvedGradient.ColorSpace.InterpolatableColor
            if lhsLocation == rhsLocation {
                stop = stops[lhsIndex]
                rhsColor = other.stops[rhsIndex].color
                lhsIndex += 1
                rhsIndex += 1
            } else if lhsLocation < rhsLocation {
                stop = stops[lhsIndex]
                rhsColor = sample(other.stops, at: lhsLocation, next: rhsIndex)
                lhsIndex += 1
            } else {
                stop = Stop(color: sample(stops, at: rhsLocation, next: lhsIndex),
                            location: rhsLocation, interpolation: nil)
                rhsColor = other.stops[rhsIndex].color
                rhsIndex += 1
            }
            stop.color.r += rhsColor.r * factor
            stop.color.g += rhsColor.g * factor
            stop.color.b += rhsColor.b * factor
            stop.color.a += rhsColor.a * factor
            merged.append(stop)
        }
        stops = merged
    }
}

extension ResolvedGradientVector {
    init(_ gradient: ResolvedGradient) {
        stops = []
        stops.reserveCapacity(gradient.stops.count)
        for stop in gradient.stops {
            stops.append(Stop(color: gradient.colorSpace.convertIn(stop.color),
                              location: stop.location, interpolation: stop.interpolation))
        }
        colorSpace = gradient.colorSpace
        headroom = gradient.headroom
    }
}
