//
//  File: UnitCurve.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct UnitCurveAnimation: InternalCustomAnimation {
    var duration: TimeInterval
    var curve: UnitCurve

    var function: Animation.Function {
        curve.animationFunction(duration: duration)
    }

    var animationBox: AnimationBoxBase {
        UnitCurveAnimationBox(curve: curve, duration: duration)
    }
}

extension Animation {
    public static func easeInOut(duration: TimeInterval) -> Animation {
        timingCurve(0.42, 0.0, 0.58, 1.0, duration: duration)
    }

    public static var easeInOut: Animation {
        timingCurve(0.42, 0.0, 0.58, 1.0)
    }

    public static func easeIn(duration: TimeInterval) -> Animation {
        timingCurve(0.42, 0.0, 1.0, 1.0, duration: duration)
    }

    public static var easeIn: Animation {
        timingCurve(0.42, 0.0, 1.0, 1.0)
    }

    public static func easeOut(duration: TimeInterval) -> Animation {
        timingCurve(0.0, 0.0, 0.58, 1.0, duration: duration)
    }

    public static var easeOut: Animation {
        timingCurve(0.0, 0.0, 0.58, 1.0)
    }

    public static func linear(duration: TimeInterval) -> Animation {
        timingCurve(0.0, 0.0, 1.0, 1.0, duration: duration)
    }

    public static var linear: Animation {
        timingCurve(0.0, 0.0, 1.0, 1.0)
    }

    public static func timingCurve(
        _ p1x: Double,
        _ p1y: Double,
        _ p2x: Double,
        _ p2y: Double,
        duration: TimeInterval = 0.35
    ) -> Animation {
        let curve = UnitCurve.CubicSolver(
            startControlPoint: UnitPoint(x: p1x, y: p1y),
            endControlPoint: UnitPoint(x: p2x, y: p2y)
        )
        return Animation(box: BezierAnimationBox(curve: curve, duration: duration))
    }

    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation {
        if let bezier = curve.cubicSolverForAnimation {
            return Animation(box: BezierAnimationBox(curve: bezier, duration: duration))
        }
        return Animation(box: UnitCurveAnimationBox(curve: curve, duration: duration))
    }
}

public struct UnitCurve: Sendable, Hashable {
    struct CubicSolver: Sendable, Hashable {
        private static let precision = 1.0 / 1_048_576.0

        let ax, bx, cx, ay, by, cy: Double

        init(startControlPoint: UnitPoint, endControlPoint: UnitPoint) {
            let c1x = Double(startControlPoint.x)
            let c1y = Double(startControlPoint.y)
            let c2x = Double(endControlPoint.x)
            let c2y = Double(endControlPoint.y)
            cx = 3.0 * c1x
            bx = 3.0 * (c2x - c1x) - cx
            ax = 1.0 - cx - bx
            cy = 3.0 * c1y
            by = 3.0 * (c2y - c1y) - cy
            ay = 1.0 - cy - by
        }

        init(
            clampingStartControlPoint startControlPoint: UnitPoint,
            endControlPoint: UnitPoint
        ) {
            self.init(
                startControlPoint: UnitPoint(
                    x: min(max(startControlPoint.x, 0), 1),
                    y: startControlPoint.y
                ),
                endControlPoint: UnitPoint(
                    x: min(max(endControlPoint.x, 0), 1),
                    y: endControlPoint.y
                )
            )
        }

        var controlPointsForAnimation: (startControlPoint: CGPoint, endControlPoint: CGPoint) {
            let first = CGPoint(x: cx / 3.0, y: cy / 3.0)
            let second = CGPoint(
                x: bx / 3.0 + 2.0 * first.x,
                y: by / 3.0 + 2.0 * first.y
            )
            return (first, second)
        }

        func solve(x: Double) -> Double {
            value(at: x)
        }

        func value(at progress: Double) -> Double {
            Self.quantize(
                sampleY(solveX(progress, epsilon: Self.precision))
            )
        }

        func velocity(at progress: Double) -> Double {
            let parameter = solveX(progress, epsilon: Self.precision)
            let dx = sampleDerivativeX(parameter)
            let dy = sampleDerivativeY(parameter)
            if dx == dy {
                return 1
            }
            if dx == 0 {
                return dy < 0 ? -.infinity : .infinity
            }
            return Self.quantize(dy / dx)
        }

        func yDerivative(atX x: Double, epsilon: Double = 1e-6) -> Double {
            sampleDerivativeY(solveX(x, epsilon: epsilon))
        }

        private func sampleX(_ t: Double) -> Double {
            ((ax * t + bx) * t + cx) * t
        }

        private func sampleY(_ t: Double) -> Double {
            ((ay * t + by) * t + cy) * t
        }

        private func sampleDerivativeX(_ t: Double) -> Double {
            (3.0 * ax * t + 2.0 * bx) * t + cx
        }

        private func sampleDerivativeY(_ t: Double) -> Double {
            (3.0 * ay * t + 2.0 * by) * t + cy
        }

        private func solveX(_ x: Double, epsilon: Double) -> Double {
            var t = x
            for _ in 0..<8 {
                let x2 = sampleX(t) - x
                if abs(x2) < epsilon { return t }
                let d2 = sampleDerivativeX(t)
                if abs(d2) < epsilon { break }
                t -= x2 / d2
            }

            guard x >= 0, x <= 1 else {
                return 0
            }
            var low: Double = 0
            var high: Double = 1
            t = x
            for _ in 0..<1024 where low < high {
                let x2 = sampleX(t)
                if abs(x2 - x) < epsilon { return t }
                if x > x2 { low = t } else { high = t }
                t = (high - low) * 0.5 + low
            }
            return t
        }

        private static func quantize(_ value: Double) -> Double {
            (value / precision).rounded() * precision
        }
    }

    private enum Function: Sendable, Hashable {
        case linear
        case bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint)
        case circularEaseIn
        case circularEaseOut
        case circularEaseInOut
    }

    private let function: Function

    private init(function: Function) {
        self.function = function
    }

    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(function: .bezier(
            startControlPoint: startControlPoint,
            endControlPoint: endControlPoint
        ))
    }

    public func value(at progress: Double) -> Double {
        switch function {
        case .linear:
            return progress
        case let .bezier(startControlPoint, endControlPoint):
            return CubicSolver(
                clampingStartControlPoint: startControlPoint,
                endControlPoint: endControlPoint
            ).value(at: min(max(progress, 0), 1))
        case .circularEaseIn:
            return 1 - sqrt(1 - progress * progress)
        case .circularEaseOut:
            let remaining = 1 - progress
            return sqrt(1 - remaining * remaining)
        case .circularEaseInOut:
            if progress <= 0.5 {
                let scaled = 2 * progress
                return (1 - sqrt(1 - scaled * scaled)) / 2
            }
            let scaled = 2 - 2 * progress
            return (1 + sqrt(1 - scaled * scaled)) / 2
        }
    }

    public func velocity(at progress: Double) -> Double {
        switch function {
        case .linear:
            return 1
        case let .bezier(startControlPoint, endControlPoint):
            return CubicSolver(
                clampingStartControlPoint: startControlPoint,
                endControlPoint: endControlPoint
            ).velocity(at: min(max(progress, 0), 1))
        case .circularEaseIn:
            return Self.circularVelocity(numerator: progress, denominator: 1 - progress * progress)
        case .circularEaseOut:
            let remaining = 1 - progress
            return Self.circularVelocity(numerator: remaining, denominator: 1 - remaining * remaining)
        case .circularEaseInOut:
            if progress <= 0.5 {
                let scaled = 2 * progress
                return Self.circularVelocity(numerator: scaled, denominator: 1 - scaled * scaled)
            }
            let scaled = 2 - 2 * progress
            return Self.circularVelocity(numerator: scaled, denominator: 1 - scaled * scaled)
        }
    }

    public var inverse: UnitCurve {
        switch function {
        case .linear:
            return .linear
        case let .bezier(startControlPoint, endControlPoint):
            return UnitCurve.bezier(
                startControlPoint: UnitPoint(x: startControlPoint.y, y: startControlPoint.x),
                endControlPoint: UnitPoint(x: endControlPoint.y, y: endControlPoint.x)
            )
        case .circularEaseIn:
            return .circularEaseOut
        case .circularEaseOut:
            return .circularEaseIn
        case .circularEaseInOut:
            return .circularEaseInOut
        }
    }

    fileprivate var bezierControlPointsForAnimation: (startControlPoint: UnitPoint, endControlPoint: UnitPoint)? {
        switch function {
        case .linear:
            return (UnitPoint(x: 0, y: 0), UnitPoint(x: 1, y: 1))
        case let .bezier(startControlPoint, endControlPoint):
            return (startControlPoint, endControlPoint)
        case .circularEaseIn, .circularEaseOut, .circularEaseInOut:
            return nil
        }
    }

    fileprivate var cubicSolverForAnimation: CubicSolver? {
        guard let controlPoints = bezierControlPointsForAnimation else {
            return nil
        }
        return CubicSolver(
            startControlPoint: controlPoints.startControlPoint,
            endControlPoint: controlPoints.endControlPoint
        )
    }

    fileprivate func animationFunction(duration: TimeInterval) -> Animation.Function {
        switch function {
        case .linear:
            return .linear(duration)
        case let .bezier(startControlPoint, endControlPoint):
            return .bezier(
                duration,
                CGPoint(x: startControlPoint.x, y: startControlPoint.y),
                CGPoint(x: endControlPoint.x, y: endControlPoint.y)
            )
        case .circularEaseIn:
            return .circularEaseIn(duration)
        case .circularEaseOut:
            return .circularEaseOut(duration)
        case .circularEaseInOut:
            return .circularEaseInOut(duration)
        }
    }

    private static func circularVelocity(numerator: Double, denominator: Double) -> Double {
        abs(numerator) / sqrt(denominator)
    }
}

extension UnitCurve {
    public static let linear = UnitCurve(function: .linear)

    public static let easeIn = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.42, y: 0),
        endControlPoint: UnitPoint(x: 1, y: 1)
    )

    public static let easeOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0, y: 0),
        endControlPoint: UnitPoint(x: 0.58, y: 1)
    )

    public static let easeInOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.42, y: 0),
        endControlPoint: UnitPoint(x: 0.58, y: 1)
    )

    public static let circularEaseIn = UnitCurve(function: .circularEaseIn)
    public static let circularEaseOut = UnitCurve(function: .circularEaseOut)
    public static let circularEaseInOut = UnitCurve(function: .circularEaseInOut)
}
