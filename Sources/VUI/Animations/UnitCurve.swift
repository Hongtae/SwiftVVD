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

        var controlPointsForAnimation: (startControlPoint: CGPoint, endControlPoint: CGPoint) {
            let first = CGPoint(x: cx / 3.0, y: cy / 3.0)
            let second = CGPoint(
                x: bx / 3.0 + 2.0 * first.x,
                y: by / 3.0 + 2.0 * first.y
            )
            return (first, second)
        }

        func solve(x: Double, epsilon: Double = 1e-6) -> Double {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            return sampleY(solveCurveX(x, epsilon: epsilon))
        }

        func derivative(x: Double, epsilon: Double = 1e-6) -> Double {
            if x <= 0 { return derivative(at: 0) }
            if x >= 1 { return derivative(at: 1) }
            return derivative(at: solveCurveX(x, epsilon: epsilon))
        }

        func yDerivative(atX x: Double, epsilon: Double = 1e-6) -> Double {
            if x <= 0 { return sampleDerivativeY(0) }
            if x >= 1 { return sampleDerivativeY(1) }
            return sampleDerivativeY(solveCurveX(x, epsilon: epsilon))
        }

        private func derivative(at t: Double) -> Double {
            let dx = sampleDerivativeX(t)
            let dy = sampleDerivativeY(t)

            if abs(dx) > 1e-12 {
                return dy / dx
            }
            if abs(dy) <= 1e-12 {
                return t <= 0 ? 1 : 0
            }
            return dy > 0 ? .infinity : -.infinity
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

        private func solveCurveX(_ x: Double, epsilon: Double) -> Double {
            var t = x
            for _ in 0..<8 {
                let x2 = sampleX(t) - x
                if abs(x2) < epsilon { return t }
                let d2 = sampleDerivativeX(t)
                if abs(d2) < 1e-6 { break }
                t -= x2 / d2
            }

            var low: Double = 0
            var high: Double = 1
            t = x
            while low < high {
                let x2 = sampleX(t)
                if abs(x2 - x) < epsilon { return t }
                if x > x2 { low = t } else { high = t }
                t = (high - low) * 0.5 + low
            }
            return t
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
                startControlPoint: startControlPoint,
                endControlPoint: endControlPoint
            ).solve(x: progress)
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
                startControlPoint: startControlPoint,
                endControlPoint: endControlPoint
            ).derivative(x: progress)
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

struct TimingFunction {
    private let ax, bx, cx, ay, by, cy: Double

    /// Initializer for custom control points (P1 and P2).
    ///
    /// Standard Presets (c1x, c1y, c2x, c2y):
    /// - Linear:      (0.00, 0.00, 1.00, 1.00)
    /// - Ease-In:     (0.42, 0.00, 1.00, 1.00)
    /// - Ease-Out:    (0.00, 0.00, 0.58, 1.00)
    /// - Ease-In-Out: (0.42, 0.00, 0.58, 1.00)
    ///
    /// Material Design / Modern UI:
    /// - FastOutSlowIn: (0.40, 0.00, 0.20, 1.00) // Standard Easing
    init(controlPoints c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double) {
        cx = 3.0 * c1x
        bx = 3.0 * (c2x - c1x) - cx
        ax = 1.0 - cx - bx
        cy = 3.0 * c1y
        by = 3.0 * (c2y - c1y) - cy
        ay = 1.0 - cy - by
    }

    init(controlPoints startControlPoint: UnitPoint, _ endControlPoint: UnitPoint) {
        self.init(
            controlPoints: Double(startControlPoint.x),
            Double(startControlPoint.y),
            Double(endControlPoint.x),
            Double(endControlPoint.y)
        )
    }

    /// Transforms time ratio (0-1) to eased progress weight (0-1).
    /// - Parameters:
    ///   - x: The current time ratio (0.0 to 1.0).
    ///   - epsilon: The required precision. Defaults to 1e-6 for UI tasks.
    func solve(x: Double, epsilon: Double = 1e-6) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return sampleY(solveCurveX(x, epsilon: epsilon))
    }

    /// Computes the derivative (velocity) at a given time ratio.
    /// - Parameters:
    ///   - x: The current time ratio (0.0 to 1.0).
    ///   - epsilon: The required precision. Defaults to 1e-6 for UI tasks.
    /// - Returns: The rate of change (dy/dx) at the given time.
    func derivative(x: Double, epsilon: Double = 1e-6) -> Double {
        if x <= 0 { return derivative(at: 0) }
        if x >= 1 { return derivative(at: 1) }

        let t = solveCurveX(x, epsilon: epsilon)
        return derivative(at: t)
    }

    private func derivative(at t: Double) -> Double {
        let dx = sampleDerivativeX(t)
        let dy = sampleDerivativeY(t)

        if abs(dx) > 1e-12 {
            return dy / dx
        }
        if abs(dy) <= 1e-12 {
            return t <= 0 ? 1 : 0
        }
        return dy > 0 ? .infinity : -.infinity
    }

    private func sampleX(_ t: Double) -> Double {
        return ((ax * t + bx) * t + cx) * t
    }

    private func sampleY(_ t: Double) -> Double {
        return ((ay * t + by) * t + cy) * t
    }

    private func sampleDerivativeX(_ t: Double) -> Double {
        return (3.0 * ax * t + 2.0 * bx) * t + cx
    }

    private func sampleDerivativeY(_ t: Double) -> Double {
        return (3.0 * ay * t + 2.0 * by) * t + cy
    }

    private func solveCurveX(_ x: Double, epsilon: Double) -> Double {
        var t = x
        // 1. Newton's Method for fast convergence
        for _ in 0..<8 {
            let x2 = sampleX(t) - x
            if abs(x2) < epsilon { return t }
            let d2 = sampleDerivativeX(t)
            if abs(d2) < 1e-6 { break }
            t -= x2 / d2
        }

        // 2. Bisection Fallback for guaranteed reliability
        var low: Double = 0, high: Double = 1
        t = x
        while low < high {
            let x2 = sampleX(t)
            if abs(x2 - x) < epsilon { return t }
            if x > x2 { low = t } else { high = t }
            t = (high - low) * 0.5 + low
        }
        return t
    }
}
