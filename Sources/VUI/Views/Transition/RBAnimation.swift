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
    private enum Modifier: Hashable {
        case delay(Double)
        case speed(Double)
        case repeatCount(Double, Bool)
    }

    // Local representation of the supported curve forms used by the interpolator.
    private enum Curve: Hashable {
        case bezier(duration: Double, controlPoint1: CGPoint, controlPoint2: CGPoint)
        case preset(duration: Double, preset: Preset)
        case sampled(duration: Double, points: [SampledPoint])
        case spring(
            duration: Double,
            mass: Double,
            stiffness: Double,
            damping: Double,
            initialVelocity: Double
        )
        case linear(duration: Double)

        var duration: Double {
            switch self {
            case let .bezier(duration, _, _):
                return max(duration, 0)
            case let .preset(duration, preset):
                return preset.activeDuration(for: duration)
            case let .sampled(duration, _),
                 let .spring(duration, _, _, _, _),
                 let .linear(duration):
                return max(duration, 0)
            }
        }

        func evaluate(at time: Double) -> Float {
            switch self {
            case let .bezier(duration, controlPoint1, controlPoint2):
                let progress = clampedProgress(time: time, duration: duration)
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
            case let .preset(duration, preset):
                return preset.evaluate(at: time, duration: duration)
            case let .sampled(duration, points):
                let progress = clampedProgress(time: time, duration: duration)
                guard points.count > 1 else { return Float(progress) }
                let sampleProgress = Float(progress)
                let first = points[0]
                guard sampleProgress > first.progress else { return first.value }
                for index in points.indices.dropFirst() {
                    let upper = points[index]
                    guard sampleProgress <= upper.progress else { continue }
                    let lower = points[points.index(before: index)]
                    let span = upper.progress - lower.progress
                    guard span != 0 else { return upper.value }
                    let fraction = (sampleProgress - lower.progress) / span
                    return lower.value + (upper.value - lower.value) * fraction
                }
                return points[points.index(before: points.endIndex)].value
            case let .spring(_, mass, stiffness, damping, initialVelocity):
                return Float(SpringTiming.value(
                    at: max(time, 0),
                    mass: mass,
                    stiffness: stiffness,
                    damping: damping,
                    initialVelocity: initialVelocity
                ))
            case let .linear(duration):
                let progress = clampedProgress(time: time, duration: duration)
                return Float(progress)
            }
        }

        func speed(at time: Double) -> Double {
            switch self {
            case let .bezier(duration, controlPoint1, controlPoint2):
                guard duration > 0 else { return 0 }
                let progress = clampedProgress(time: time, duration: duration)
                guard progress > 0, progress < 1 else { return 0 }
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
                return abs(solver.yDerivative(atX: progress, epsilon: 1e-4) / duration)
            case let .preset(duration, preset):
                let activeDuration = preset.activeDuration(for: duration)
                guard activeDuration > 0, time > 0, time < activeDuration else { return 0 }
                return abs(preset.speed(at: time, duration: duration))
            case let .sampled(duration, points):
                guard duration > 0 else { return 0 }
                let progress = clampedProgress(time: time, duration: duration)
                guard progress > 0, progress < 1, points.count > 1 else { return 0 }
                let sampleProgress = Float(progress)
                for index in points.indices.dropFirst() {
                    let upper = points[index]
                    guard sampleProgress <= upper.progress else { continue }
                    let lower = points[points.index(before: index)]
                    let progressSpan = upper.progress - lower.progress
                    guard progressSpan != 0 else { return 0 }
                    return abs(Double(upper.value - lower.value) / Double(progressSpan) / duration)
                }
                return 0
            case let .spring(_, mass, stiffness, damping, initialVelocity):
                return abs(SpringTiming.velocity(
                    at: max(time, 0),
                    mass: mass,
                    stiffness: stiffness,
                    damping: damping,
                    initialVelocity: initialVelocity
                ))
            case let .linear(duration):
                guard duration > 0 else { return 0 }
                let progress = clampedProgress(time: time, duration: duration)
                guard progress > 0, progress < 1 else { return 0 }
                return 1 / duration
            }
        }

        private func clampedProgress(time: Double, duration: Double) -> Double {
            guard duration > 0 else { return 1 }
            return min(max(time / duration, 0), 1)
        }
    }

    private struct SampledPoint: Hashable {
        var progress: Float
        var value: Float
    }

    // RenderBox keeps ignored second curve installs visible to equality without
    // making equal ignored installs from different objects compare equal.
    private struct IgnoredCurveInstall: Hashable {
        var id = UUID()
    }

    private enum Preset: UInt32 {
        case linear = 0
        case smoothstep = 1
        case easeIn = 2
        case easeOut = 3
        case easeInOut = 4
        case springCritical = 5
        case springDamping075 = 6
        case springDamping055 = 7
        case circularEaseIn = 8
        case circularEaseOut = 9
        case circularEaseInOut = 10

        func activeDuration(for duration: Double) -> Double {
            let duration = max(duration, 0)
            switch self {
            case .springCritical:
                return duration * 1.5
            case .springDamping075:
                return duration * 1.65
            case .springDamping055:
                return duration * 2.075
            default:
                return duration
            }
        }

        func evaluate(at time: Double, duration: Double) -> Float {
            guard duration > 0 else { return 1 }
            let progress = max(time / duration, 0)
            let clamped = min(progress, 1)

            switch self {
            case .linear:
                return Float(clamped)
            case .smoothstep:
                return Float(clamped * clamped * (3 - 2 * clamped))
            case .easeIn:
                return Float(UnitCurve.easeIn.value(at: clamped))
            case .easeOut:
                return Float(UnitCurve.easeOut.value(at: clamped))
            case .easeInOut:
                return Float(UnitCurve.easeInOut.value(at: clamped))
            case .springCritical:
                return Float(SpringTiming.value(
                    at: progress,
                    naturalFrequency: 2 * Double.pi,
                    dampingRatio: 1,
                    initialVelocity: 0
                ))
            case .springDamping075:
                return Float(SpringTiming.value(
                    at: progress,
                    naturalFrequency: 2 * Double.pi,
                    dampingRatio: 0.75,
                    initialVelocity: 0
                ))
            case .springDamping055:
                return Float(SpringTiming.value(
                    at: progress,
                    naturalFrequency: 2 * Double.pi,
                    dampingRatio: 0.55,
                    initialVelocity: 0
                ))
            case .circularEaseIn:
                return Float(UnitCurve.circularEaseIn.value(at: clamped))
            case .circularEaseOut:
                return Float(UnitCurve.circularEaseOut.value(at: clamped))
            case .circularEaseInOut:
                return Float(UnitCurve.circularEaseInOut.value(at: clamped))
            }
        }

        func speed(at time: Double, duration: Double) -> Double {
            guard duration > 0 else { return 0 }
            let progress = max(time / duration, 0)
            let clamped = min(progress, 1)

            switch self {
            case .linear:
                return 1 / duration
            case .smoothstep:
                return (6 * clamped * (1 - clamped)) / duration
            case .easeIn:
                return UnitCurve.easeIn.velocity(at: clamped) / duration
            case .easeOut:
                return UnitCurve.easeOut.velocity(at: clamped) / duration
            case .easeInOut:
                return UnitCurve.easeInOut.velocity(at: clamped) / duration
            case .springCritical:
                return SpringTiming.velocity(
                    at: progress,
                    naturalFrequency: 2 * Double.pi,
                    dampingRatio: 1,
                    initialVelocity: 0
                ) / duration
            case .springDamping075:
                return SpringTiming.velocity(
                    at: progress,
                    naturalFrequency: 2 * Double.pi,
                    dampingRatio: 0.75,
                    initialVelocity: 0
                ) / duration
            case .springDamping055:
                return SpringTiming.velocity(
                    at: progress,
                    naturalFrequency: 2 * Double.pi,
                    dampingRatio: 0.55,
                    initialVelocity: 0
                ) / duration
            case .circularEaseIn:
                return UnitCurve.circularEaseIn.velocity(at: clamped) / duration
            case .circularEaseOut:
                return UnitCurve.circularEaseOut.velocity(at: clamped) / duration
            case .circularEaseInOut:
                return UnitCurve.circularEaseInOut.velocity(at: clamped) / duration
            }
        }
    }

    private enum SpringTiming {
        static func value(
            at time: Double,
            mass: Double,
            stiffness: Double,
            damping: Double,
            initialVelocity: Double
        ) -> Double {
            guard mass > 0, stiffness > 0 else { return 1 }

            let naturalFrequency = sqrt(stiffness / mass)
            let dampingRatio = damping / (2 * sqrt(stiffness * mass))
            return value(
                at: time,
                naturalFrequency: naturalFrequency,
                dampingRatio: dampingRatio,
                initialVelocity: initialVelocity
            )
        }

        static func value(
            at time: Double,
            naturalFrequency: Double,
            dampingRatio: Double,
            initialVelocity: Double
        ) -> Double {
            let time = max(time, 0)
            guard naturalFrequency > 0 else { return 1 }

            if dampingRatio < 1 {
                let dampedFrequency = naturalFrequency * sqrt(1 - dampingRatio * dampingRatio)
                let coefficient = (dampingRatio * naturalFrequency - initialVelocity) / dampedFrequency
                let oscillation = cos(dampedFrequency * time) + coefficient * sin(dampedFrequency * time)
                return 1 - exp(-dampingRatio * naturalFrequency * time) * oscillation
            }

            return 1 - (1 + (naturalFrequency - initialVelocity) * time) * exp(-naturalFrequency * time)
        }

        static func velocity(
            at time: Double,
            mass: Double,
            stiffness: Double,
            damping: Double,
            initialVelocity: Double
        ) -> Double {
            guard mass > 0, stiffness > 0 else { return 0 }

            let naturalFrequency = sqrt(stiffness / mass)
            let dampingRatio = damping / (2 * sqrt(stiffness * mass))
            return velocity(
                at: time,
                naturalFrequency: naturalFrequency,
                dampingRatio: dampingRatio,
                initialVelocity: initialVelocity
            )
        }

        static func velocity(
            at time: Double,
            naturalFrequency: Double,
            dampingRatio: Double,
            initialVelocity: Double
        ) -> Double {
            let time = max(time, 0)
            guard naturalFrequency > 0 else { return 0 }

            if dampingRatio < 1 {
                let dampedFrequency = naturalFrequency * sqrt(1 - dampingRatio * dampingRatio)
                let coefficient = (dampingRatio * naturalFrequency - initialVelocity) / dampedFrequency
                let decay = exp(-dampingRatio * naturalFrequency * time)
                let oscillation = cos(dampedFrequency * time) + coefficient * sin(dampedFrequency * time)
                return decay * (
                    dampingRatio * naturalFrequency * oscillation +
                    dampedFrequency * sin(dampedFrequency * time) -
                    coefficient * dampedFrequency * cos(dampedFrequency * time)
                )
            }

            let coefficient = naturalFrequency - initialVelocity
            let decay = exp(-naturalFrequency * time)
            return decay * (naturalFrequency * (1 + coefficient * time) - coefficient)
        }
    }

    private var pendingModifiers: [Modifier]
    private var curveModifiers: [Modifier]
    private var ignoredModifiers: [Modifier]
    private var ignoredCurveInstalls: [IgnoredCurveInstall]
    private var curve: Curve?

    override init() {
        self.pendingModifiers = []
        self.curveModifiers = []
        self.ignoredModifiers = []
        self.ignoredCurveInstalls = []
        self.curve = nil
        super.init()
    }

    private init(
        pendingModifiers: [Modifier],
        curveModifiers: [Modifier],
        ignoredModifiers: [Modifier],
        ignoredCurveInstalls: [IgnoredCurveInstall],
        curve: Curve?
    ) {
        self.pendingModifiers = pendingModifiers
        self.curveModifiers = curveModifiers
        self.ignoredModifiers = ignoredModifiers
        self.ignoredCurveInstalls = ignoredCurveInstalls
        self.curve = curve
        super.init()
    }

    var activeDuration: Double {
        guard let curve else { return 0 }
        return applyDurationModifiers(to: curve.duration)
    }

    func evaluate(atTime time: Double) -> Float {
        guard let curve else {
            return time > 0 ? 1 : 0
        }
        let localTime = applyTimeModifiers(to: time, curveDuration: curve.duration)
        return curve.evaluate(at: localTime)
    }

    func evaluateAtTime(_ time: Double) -> Float {
        evaluate(atTime: time)
    }

    func speed(atTime time: Double) -> Double {
        guard let curve else { return 0 }
        let activeDuration = applyDurationModifiers(to: curve.duration)
        guard activeDuration > 0, time > 0, time < activeDuration else { return 0 }
        let transformed = applyTimeModifiersWithScale(to: time, curveDuration: curve.duration)
        guard transformed.scale > 0 else { return 0 }
        return abs(curve.speed(at: transformed.time) * transformed.scale)
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
        guard let preset = Preset(rawValue: preset) else { return }
        installCurve(.preset(duration: duration, preset: preset))
    }

    func addRepeatCount(_ repeatCount: Double, autoreverses: Bool) {
        appendModifier(.repeatCount(repeatCount, autoreverses))
    }

    func addSampledFunction(
        withDuration duration: Double,
        count: UInt,
        values: UnsafePointer<Float>
    ) {
        let points = (0..<Int(count)).map { index in
            SampledPoint(
                progress: values[index * 2],
                value: values[index * 2 + 1]
            )
        }
        installCurve(.sampled(duration: duration, points: points))
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
        installCurve(.spring(
            duration: duration,
            mass: mass,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: initialVelocity
        ))
    }

    func removeAll() {
        pendingModifiers.removeAll()
        curveModifiers.removeAll()
        ignoredModifiers.removeAll()
        ignoredCurveInstalls.removeAll()
        curve = nil
    }

    func copy(with zone: NSZone? = nil) -> Any {
        RBAnimation(
            pendingModifiers: pendingModifiers,
            curveModifiers: curveModifiers,
            ignoredModifiers: ignoredModifiers,
            ignoredCurveInstalls: ignoredCurveInstalls,
            curve: curve
        )
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RBAnimation else {
            return false
        }
        return pendingModifiers == other.pendingModifiers &&
            curveModifiers == other.curveModifiers &&
            ignoredModifiers == other.ignoredModifiers &&
            ignoredCurveInstalls == other.ignoredCurveInstalls &&
            curve == other.curve
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(pendingModifiers)
        hasher.combine(curveModifiers)
        hasher.combine(ignoredModifiers)
        hasher.combine(ignoredCurveInstalls)
        hasher.combine(curve)
        return hasher.finalize()
    }

    var hasStoredTerms: Bool {
        curve != nil ||
            !pendingModifiers.isEmpty ||
            !curveModifiers.isEmpty ||
            !ignoredModifiers.isEmpty ||
            !ignoredCurveInstalls.isEmpty
    }

    private func appendModifier(_ modifier: Modifier) {
        if curve == nil {
            pendingModifiers.append(modifier)
        } else {
            ignoredModifiers.append(modifier)
        }
    }

    private func installCurve(_ curve: Curve) {
        guard self.curve == nil else {
            ignoredCurveInstalls.append(IgnoredCurveInstall())
            return
        }
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

    private func applyTimeModifiersWithScale(
        to time: Double,
        curveDuration: Double
    ) -> (time: Double, scale: Double) {
        var localTime = max(time, 0)
        var scale = 1.0
        for modifier in curveModifiers {
            switch modifier {
            case let .delay(delay):
                localTime = max(localTime - delay, 0)
            case let .speed(speed):
                if speed > 0 {
                    localTime *= speed
                    scale *= speed
                } else {
                    localTime = 0
                    scale = 0
                }
            case let .repeatCount(count, autoreverses):
                localTime = repeatedTime(
                    localTime,
                    duration: curveDuration,
                    count: count,
                    autoreverses: autoreverses
                )
            }
        }
        return (localTime, scale)
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

// Local animation table used by future display-list operation storage.
struct RBAnimationTable {
    struct Entry {
        var index: Int32
        var animation: RBAnimation
        var activeDuration: Double
    }

    var defaultAnimationIndex: Int32
    private(set) var entries: [Entry]

    init(defaultAnimationIndex: Int32 = -1) {
        self.defaultAnimationIndex = defaultAnimationIndex
        self.entries = []
    }

    @discardableResult
    mutating func internAnimation(_ animation: RBAnimation?) -> Int32 {
        guard let animation else {
            return defaultAnimationIndex
        }
        guard animation.hasStoredTerms else {
            return -1
        }

        if let entry = entries.first(where: { $0.animation.isEqual(animation) }) {
            return entry.index
        }
        guard entries.count < Int(Int32.max) else {
            fatalError("RBAnimationTable animation index overflow.")
        }

        let storedAnimation = animation.copy() as? RBAnimation ?? RBAnimation()
        let index = Int32(entries.count + 1)
        entries.append(Entry(
            index: index,
            animation: storedAnimation,
            activeDuration: storedAnimation.activeDuration
        ))
        return index
    }

    func animation(at index: Int32) -> RBAnimation? {
        guard index > 0 else { return nil }
        let offset = Int(index - 1)
        guard offset >= 0, offset < entries.count else { return nil }
        return entries[offset].animation
    }

    func activeDuration(animationIndex index: Int32) -> Double {
        animation(at: index)?.activeDuration ?? 0
    }

    func maximumDuration(animationIndex index: Int32) -> Double {
        guard index != 0 else { return 1 }
        return animation(at: index)?.activeDuration ?? 0
    }

    func evaluate(animationIndex index: Int32, sequence: UInt32 = 0, time: Double) -> Float {
        switch index {
        case -1:
            return time > 0 ? 1 : 0
        case 0, -2:
            return Float(time)
        default:
            _ = sequence
            return animation(at: index)?.evaluateAtTime(time) ?? Float(time)
        }
    }

    func maxSpeed(animationIndex index: Int32, time: Double) -> Double {
        animation(at: index)?.speed(atTime: time) ?? 0
    }

    func maxSpeed(atTime time: Double) -> Double {
        entries.reduce(0) { result, entry in
            max(result, entry.animation.speed(atTime: time))
        }
    }
}

// Per-phase sequencing offsets used when an interpolator staggers add, mix, and remove work.
final class RBAnimationSequencerEffects: NSObject {
    var delayOffset: Float
    var delayScale: Float

    override init() {
        self.delayOffset = 0
        self.delayScale = 0
        super.init()
    }
}

// Sequencing options passed to display-list interpolation for distance-based transition timing.
final class RBAnimationSequencer: NSObject {
    enum Phase {
        case added
        case mixed
        case removed
    }

    var distanceMode: Int32
    var sequencesGlyphs: Bool
    var startPoint: CGPoint
    var endPoint: CGPoint
    var added: RBAnimationSequencerEffects?
    var mixed: RBAnimationSequencerEffects?
    var removed: RBAnimationSequencerEffects?

    struct OperationAnimationRecord: Equatable {
        var animationIndex: Int32
        var delay: Float
    }

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

    func evalDelay(at point: CGPoint, phase: Phase) -> Double? {
        let effects = effects(for: phase)
        let offset = Double(effects?.delayOffset ?? 0)
        let scale = Double(effects?.delayScale ?? 0)
        guard let factor = delayFactor(at: point) else {
            return nil
        }
        let delay = offset + scale * factor
        guard delay.isFinite else {
            return nil
        }
        return delay
    }

    static func phase(forAnimatedOperationType operationType: UInt8) -> Phase {
        switch operationType {
        case 0:
            return .removed
        case 1:
            return .added
        default:
            return .mixed
        }
    }

    static func canCarryAnimationIndex(operationLowNibble operationType: UInt8) -> Bool {
        guard operationType <= 8 else {
            return true
        }
        return (0x130 & (1 << UInt32(operationType))) == 0
    }

    static func operationAnimationIndex(
        operationLowNibble operationType: UInt8,
        resolvedAnimationIndex: Int32?,
        defaultAnimationIndex: Int32
    ) -> Int32 {
        guard canCarryAnimationIndex(operationLowNibble: operationType) else {
            return -1
        }
        return resolvedAnimationIndex ?? defaultAnimationIndex
    }

    static func operationDelay(
        byAddingSequencerDelay sequencerDelay: Double?,
        to operationDelay: Float
    ) -> Float {
        guard let sequencerDelay,
              sequencerDelay.isFinite,
              sequencerDelay > 0 else {
            return operationDelay
        }
        return operationDelay + Float(sequencerDelay)
    }

    static func operationAnimationRecord(
        operationLowNibble operationType: UInt8,
        resolvedAnimationIndex: Int32?,
        defaultAnimationIndex: Int32,
        operationDelay: Float,
        sequencerDelay: Double?
    ) -> OperationAnimationRecord {
        OperationAnimationRecord(
            animationIndex: operationAnimationIndex(
                operationLowNibble: operationType,
                resolvedAnimationIndex: resolvedAnimationIndex,
                defaultAnimationIndex: defaultAnimationIndex
            ),
            delay: Self.operationDelay(
                byAddingSequencerDelay: sequencerDelay,
                to: operationDelay
            )
        )
    }

    func evalDelay(at point: CGPoint, animatedOperationType operationType: UInt8) -> Double? {
        evalDelay(at: point, phase: Self.phase(forAnimatedOperationType: operationType))
    }

    private func effects(for phase: Phase) -> RBAnimationSequencerEffects? {
        switch phase {
        case .added:
            return added
        case .mixed:
            return mixed
        case .removed:
            return removed
        }
    }

    private func delayFactor(at point: CGPoint) -> Double? {
        let dx = Double(endPoint.x - startPoint.x)
        let dy = Double(endPoint.y - startPoint.y)
        switch distanceMode {
        case 0:
            let distanceSquared = dx * dx + dy * dy
            guard distanceSquared > 0 else {
                return nil
            }
            let px = Double(point.x - startPoint.x)
            let py = Double(point.y - startPoint.y)
            return Self.clamp((dx * px + dy * py) / distanceSquared)
        case 1:
            let distance = hypot(dx, dy)
            guard distance > 0 else {
                return nil
            }
            let px = Double(point.x - startPoint.x)
            let py = Double(point.y - startPoint.y)
            return Self.clamp(hypot(px, py) / distance)
        default:
            return 0
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
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
            switch box.function {
            case let .circularEaseIn(duration):
                animation.addPreset(8, duration: duration)
            case let .circularEaseOut(duration):
                animation.addPreset(9, duration: duration)
            case let .circularEaseInOut(duration):
                animation.addPreset(10, duration: duration)
            default:
                appendSampledCurve(
                    to: animation,
                    duration: box.storedDuration,
                    valueAtProgress: box.curve.value(at:)
                )
            }
        case is DefaultAnimationBox:
            appendFluidSpring(
                to: animation,
                response: 0.5,
                dampingFraction: 1.0,
                initialVelocity: 0
            )
        case let box as FluidSpringAnimationBox:
            appendFluidSpring(
                to: animation,
                response: box.response,
                dampingFraction: box.dampingFraction,
                initialVelocity: 0
            )
        case let box as SpringAnimationBox:
            animation.addSpringDuration(
                box.duration,
                mass: box.mass,
                stiffness: box.stiffness,
                damping: box.damping,
                initialVelocity: box.initialVelocity
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

    func appendFluidSpring(
        to animation: RBAnimation,
        response: TimeInterval,
        dampingFraction: Double,
        initialVelocity: Double
    ) {
        let stiffness = fluidSpringStiffness(response: response)
        let damping = 2 * dampingFraction * sqrt(stiffness)
        animation.addSpringDuration(
            max(response, 0),
            mass: 1,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: initialVelocity
        )
    }

    func appendSampledCurve(
        to animation: RBAnimation,
        duration: Double,
        valueAtProgress: (Double) -> Double
    ) {
        let pairCount = 33
        let values = (0..<pairCount).flatMap { index -> [Float] in
            let progress = Double(index) / Double(pairCount - 1)
            return [
                Float(progress),
                Float(valueAtProgress(progress)),
            ]
        }
        values.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            animation.addSampledFunction(
                withDuration: duration,
                count: UInt(pairCount),
                values: baseAddress
            )
        }
    }
}
