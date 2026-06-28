//
//  File: RBAnimation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// RenderBox-style animation carrier used by display-list interpolators to map elapsed time
// to normalized interpolation progress.
final class RBAnimation: NSObject, NSCopying {
    // Timing transforms recorded before the curve is installed.
    private enum Modifier {
        case delay(Double)
        case speed(Double)
        case repeatCount(Double, Bool)
    }

    // Local representation of the supported curve forms used by the interpolator.
    private enum Curve {
        case bezier(duration: Double, controlPoint1: CGPoint, controlPoint2: CGPoint)
        case sampled(duration: Double, values: [Float])
        case linear(duration: Double)

        var duration: Double {
            switch self {
            case let .bezier(duration, _, _),
                 let .sampled(duration, _),
                 let .linear(duration):
                return max(duration, 0)
            }
        }

        func evaluate(at time: Double) -> Float {
            let duration = duration
            guard duration > 0 else { return 1 }
            let progress = min(max(time / duration, 0), 1)
            switch self {
            case let .bezier(_, controlPoint1, controlPoint2):
                let solver = UnitCurve.CubicSolver(
                    startControlPoint: UnitPoint(
                        x: controlPoint1.x,
                        y: controlPoint1.y
                    ),
                    endControlPoint: UnitPoint(
                        x: controlPoint2.x,
                        y: controlPoint2.y
                    )
                )
                return Float(solver.solve(x: progress))
            case let .sampled(_, values):
                guard !values.isEmpty else { return Float(progress) }
                guard values.count > 1 else { return values[0] }
                let scaled = progress * Double(values.count - 1)
                let lower = min(Int(floor(scaled)), values.count - 1)
                let upper = min(lower + 1, values.count - 1)
                let fraction = Float(scaled - Double(lower))
                return values[lower] + (values[upper] - values[lower]) * fraction
            case .linear:
                return Float(progress)
            }
        }
    }

    private var pendingModifiers: [Modifier]
    private var curveModifiers: [Modifier]
    private var curve: Curve?

    override init() {
        self.pendingModifiers = []
        self.curveModifiers = []
        self.curve = nil
        super.init()
    }

    private init(
        pendingModifiers: [Modifier],
        curveModifiers: [Modifier],
        curve: Curve?
    ) {
        self.pendingModifiers = pendingModifiers
        self.curveModifiers = curveModifiers
        self.curve = curve
        super.init()
    }

    var activeDuration: Double {
        guard let curve else { return 0 }
        return applyDurationModifiers(to: curve.duration)
    }

    func evaluate(atTime time: Double) -> Float {
        guard let curve else {
            return Float(min(max(time, 0), 1))
        }
        let localTime = applyTimeModifiers(to: time, curveDuration: curve.duration)
        return curve.evaluate(at: localTime)
    }

    func evaluateAtTime(_ time: Double) -> Float {
        evaluate(atTime: time)
    }

    func addBezierDuration(
        _ duration: Double,
        controlPoint1: CGPoint,
        controlPoint2: CGPoint
    ) {
        installCurve(
            .bezier(
                duration: duration,
                controlPoint1: controlPoint1,
                controlPoint2: controlPoint2
            )
        )
    }

    func addDelay(_ delay: Double) {
        appendModifier(.delay(delay))
    }

    func addPreset(_ preset: UInt32, duration: Double) {
        installCurve(.linear(duration: duration))
    }

    func addRepeatCount(_ repeatCount: Double, autoreverses: Bool) {
        appendModifier(.repeatCount(repeatCount, autoreverses))
    }

    func addSampledFunction(
        withDuration duration: Double,
        count: UInt,
        values: UnsafePointer<Float>
    ) {
        let samples = (0..<Int(count)).map { values[$0] }
        installCurve(.sampled(duration: duration, values: samples))
    }

    func addSpeed(_ speed: Double) {
        appendModifier(.speed(speed))
    }

    func addSpringDuration(
        _ duration: Double,
        mass: Double,
        stiffness: Double,
        damping: Double,
        initialVelocity: Double
    ) {
        installCurve(.linear(duration: duration))
    }

    func removeAll() {
        pendingModifiers.removeAll()
        curveModifiers.removeAll()
        curve = nil
    }

    func copy(with zone: NSZone? = nil) -> Any {
        RBAnimation(
            pendingModifiers: pendingModifiers,
            curveModifiers: curveModifiers,
            curve: curve
        )
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RBAnimation else {
            return false
        }
        return activeDuration == other.activeDuration
    }

    private func appendModifier(_ modifier: Modifier) {
        if curve == nil {
            pendingModifiers.append(modifier)
        }
    }

    private func installCurve(_ curve: Curve) {
        guard self.curve == nil else { return }
        self.curve = curve
        self.curveModifiers = pendingModifiers
    }

    private func applyDurationModifiers(to duration: Double) -> Double {
        var result = duration
        for modifier in curveModifiers {
            switch modifier {
            case let .delay(delay):
                result = max(result + delay, 0)
            case let .speed(speed):
                result = speed > 0 ? result / speed : .infinity
            case let .repeatCount(count, _):
                if count == .infinity {
                    result = .infinity
                } else {
                    result = max(result * max(count, 0), 0)
                }
            }
        }
        return result
    }

    private func applyTimeModifiers(to time: Double, curveDuration: Double) -> Double {
        var localTime = max(time, 0)
        for modifier in curveModifiers {
            switch modifier {
            case let .delay(delay):
                localTime = max(localTime - delay, 0)
            case let .speed(speed):
                localTime = speed > 0 ? localTime * speed : 0
            case let .repeatCount(count, autoreverses):
                localTime = repeatedTime(
                    localTime,
                    duration: curveDuration,
                    count: count,
                    autoreverses: autoreverses
                )
            }
        }
        return localTime
    }

    private func repeatedTime(
        _ time: Double,
        duration: Double,
        count: Double,
        autoreverses: Bool
    ) -> Double {
        guard duration > 0 else { return 0 }
        if count.isFinite, count > 0 {
            let totalDuration = duration * count
            if time >= totalDuration {
                let roundedCount = Int(count.rounded(.towardZero))
                let endsReversed = autoreverses && roundedCount.isMultiple(of: 2)
                return endsReversed ? 0 : duration
            }
        }

        let cycleIndex = Int(floor(time / duration))
        var cycleTime = time.truncatingRemainder(dividingBy: duration)
        if cycleTime < 0 {
            cycleTime += duration
        }
        if autoreverses && !cycleIndex.isMultiple(of: 2) {
            cycleTime = duration - cycleTime
        }
        return cycleTime
    }
}

// Per-phase sequencing offsets used when an interpolator staggers add, mix, and remove work.
final class RBAnimationSequencerEffects: NSObject {
    var delayOffset: Float
    var delayScale: Float

    override init() {
        self.delayOffset = 0
        self.delayScale = 1
        super.init()
    }
}

// Sequencing options passed to display-list interpolation for distance-based transition timing.
final class RBAnimationSequencer: NSObject {
    var distanceMode: Int32
    var sequencesGlyphs: Bool
    var startPoint: CGPoint
    var endPoint: CGPoint
    var added: RBAnimationSequencerEffects?
    var mixed: RBAnimationSequencerEffects?
    var removed: RBAnimationSequencerEffects?

    override init() {
        self.distanceMode = 0
        self.sequencesGlyphs = false
        self.startPoint = .zero
        self.endPoint = .zero
        self.added = nil
        self.mixed = nil
        self.removed = nil
        super.init()
    }
}

// Lowers VUI Animation boxes into the local RenderBox-style animation carrier.
extension Animation {
    var rbAnimation: RBAnimation {
        let animation = RBAnimation()
        box.append(to: animation)
        return animation
    }
}

private extension AnimationBoxBase {
    func append(to animation: RBAnimation) {
        switch self {
        case let box as DelayAnimationBox:
            animation.addDelay(box.delay)
            box.base.append(to: animation)
        case let box as SpeedAnimationBox:
            animation.addSpeed(box.speed)
            box.base.append(to: animation)
        case let box as RepeatAnimationBox:
            animation.addRepeatCount(
                box.repeatCount.map { Double($0) } ?? .infinity,
                autoreverses: box.autoreverses
            )
            box.base.append(to: animation)
        case let box as LogicalCompletionAnimationBox:
            box.base.append(to: animation)
        case let box as BezierAnimationBox:
            let points = box.curve.controlPointsForAnimation
            animation.addBezierDuration(
                box.storedDuration,
                controlPoint1: points.startControlPoint,
                controlPoint2: points.endControlPoint
            )
        case let box as UnitCurveAnimationBox:
            appendSampledCurve(
                to: animation,
                duration: box.storedDuration,
                valueAtProgress: box.curve.value(at:)
            )
        default:
            let duration = max(self.duration, 0)
            appendSampledCurve(
                to: animation,
                duration: duration.isFinite ? duration : 1,
                valueAtProgress: value(at:)
            )
        }
    }

    func appendSampledCurve(
        to animation: RBAnimation,
        duration: Double,
        valueAtProgress: (Double) -> Double
    ) {
        let count = 33
        let values = (0..<count).map { index in
            Float(valueAtProgress(Double(index) / Double(count - 1)))
        }
        values.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            animation.addSampledFunction(
                withDuration: duration,
                count: UInt(buffer.count),
                values: baseAddress
            )
        }
    }
}
