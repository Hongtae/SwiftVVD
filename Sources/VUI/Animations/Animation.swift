//
//  File: Animation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
class AnimationBoxBase: CustomStringConvertible, @unchecked Sendable {
    // Box subclasses keep the public Animation value small while preserving
    // modifier composition such as delay, speed, repeat, and spring variants.
    var duration: TimeInterval { 0 }

    @usableFromInline
    var description: String {
        String(describing: type(of: self))
    }

    func value(at progress: Double) -> Double {
        progress
    }
}

@usableFromInline
final class DefaultAnimationBox: AnimationBoxBase, @unchecked Sendable {
    private let curve = UnitCurve.easeInOut

    override var duration: TimeInterval {
        0.35
    }

    override func value(at progress: Double) -> Double {
        curve.value(at: progress)
    }
}

@usableFromInline
final class BezierAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let curve: UnitCurve
    let storedDuration: TimeInterval

    init(curve: UnitCurve, duration: TimeInterval) {
        self.curve = curve
        self.storedDuration = duration
    }

    override var duration: TimeInterval {
        storedDuration
    }

    override func value(at progress: Double) -> Double {
        curve.value(at: progress)
    }
}

@usableFromInline
final class DelayAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let base: AnimationBoxBase
    let delay: TimeInterval

    init(base: AnimationBoxBase, delay: TimeInterval) {
        self.base = base
        self.delay = delay
    }

    override var duration: TimeInterval {
        max(0, base.duration + delay)
    }

    override func value(at progress: Double) -> Double {
        guard base.duration > 0 else { return base.value(at: 1) }
        let localTime = progress * duration - delay
        let localProgress = min(max(localTime / base.duration, 0), 1)
        return base.value(at: localProgress)
    }
}

@usableFromInline
final class SpeedAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let base: AnimationBoxBase
    let speed: Double

    init(base: AnimationBoxBase, speed: Double) {
        self.base = base
        self.speed = speed
    }

    override var duration: TimeInterval {
        guard speed > 0 else { return .infinity }
        return base.duration / speed
    }

    override func value(at progress: Double) -> Double {
        guard speed > 0 else { return base.value(at: 0) }
        return base.value(at: progress)
    }
}

@usableFromInline
final class RepeatAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let base: AnimationBoxBase
    let repeatCount: Int?
    let autoreverses: Bool

    init(base: AnimationBoxBase, repeatCount: Int?, autoreverses: Bool) {
        self.base = base
        self.repeatCount = repeatCount
        self.autoreverses = autoreverses
    }

    private var resolvedRepeatCount: Int {
        max(repeatCount ?? 1, 1)
    }

    override var duration: TimeInterval {
        guard let repeatCount else { return .infinity }
        return base.duration * TimeInterval(max(repeatCount, 1))
    }

    override func value(at progress: Double) -> Double {
        guard base.duration > 0 else { return base.value(at: 1) }
        let cycles: Double
        if let repeatCount {
            cycles = Double(max(repeatCount, 1))
        } else {
            cycles = 1
        }

        let rawCycle: Double
        if repeatCount == nil {
            rawCycle = max(progress, 0).truncatingRemainder(dividingBy: 1)
        } else {
            rawCycle = min(max(progress, 0), 1) * cycles
        }

        if repeatCount != nil, rawCycle >= cycles {
            let endsReversed = autoreverses && resolvedRepeatCount.isMultiple(of: 2)
            return base.value(at: endsReversed ? 0 : 1)
        }

        let cycleIndex = Int(floor(rawCycle))
        var localProgress = rawCycle - Double(cycleIndex)
        if autoreverses && !cycleIndex.isMultiple(of: 2) {
            localProgress = 1 - localProgress
        }
        return base.value(at: min(max(localProgress, 0), 1))
    }
}

@usableFromInline
final class FluidSpringAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let response: TimeInterval
    let dampingFraction: Double
    let blendDuration: TimeInterval

    init(response: TimeInterval, dampingFraction: Double, blendDuration: TimeInterval) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
    }

    override var duration: TimeInterval {
        max(0, response + blendDuration)
    }

    override func value(at progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        let damping = max(dampingFraction, 0.001)
        let decay = exp(-damping * 6 * clamped)
        let oscillation = cos((1 + max(0, 1 - damping)) * .pi * clamped)
        return min(max(1 - decay * oscillation, 0), 1)
    }
}

@usableFromInline
final class SpringAnimationBox: AnimationBoxBase, @unchecked Sendable {
    let mass: Double
    let stiffness: Double
    let damping: Double
    let initialVelocity: Double

    init(mass: Double, stiffness: Double, damping: Double, initialVelocity: Double) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
        self.initialVelocity = initialVelocity
    }

    override var duration: TimeInterval {
        let naturalFrequency = sqrt(max(stiffness, 0.001) / max(mass, 0.001))
        return max(0.001, 2 * .pi / naturalFrequency)
    }

    override func value(at progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        let dampingRatio = damping / (2 * sqrt(max(stiffness * mass, 0.001)))
        let decay = exp(-max(dampingRatio, 0.001) * 6 * clamped)
        let velocityTerm = initialVelocity * clamped * decay * 0.1
        return min(max(1 - decay * cos(.pi * clamped) + velocityTerm, 0), 1)
    }
}

public struct Animation: Equatable, Sendable {
    var box: AnimationBoxBase

    @usableFromInline
    init(box: AnimationBoxBase) {
        self.box = box
    }

    public static func == (lhs: Animation, rhs: Animation) -> Bool {
        lhs.box === rhs.box
    }
}

extension Animation: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(box))
    }
}

public struct AnimationCompletionCriteria: Hashable, Sendable {
    private let storage: UInt8

    private init(storage: UInt8) {
        self.storage = storage
    }

    public static let logicallyComplete = AnimationCompletionCriteria(storage: 0)
    public static let removed = AnimationCompletionCriteria(storage: 1)
}

final class AnimationCompletionObserver: @unchecked Sendable {
    private struct Entry {
        var criteria: AnimationCompletionCriteria
        var completion: () -> Void
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var activeAnimations: Int = 0
    private var bodyFinished = false
    private var registeredAnimation = false
    private var completed = false

    // Completion observers are shared by every animatable node touched by one
    // transaction. The transaction body must finish, at least one animation must
    // register, and all registered tokens must finish before callbacks run.
    init(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        entries.append(Entry(criteria: criteria, completion: completion))
    }

    func add(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        entries.append(Entry(criteria: criteria, completion: completion))
    }

    func animationDidStart() -> AnimationCompletionToken? {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return nil }
        registeredAnimation = true
        activeAnimations += 1
        return AnimationCompletionToken(observer: self)
    }

    func bodyDidFinish() -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        bodyFinished = true
        return completionsIfReady(allowNoRegisteredAnimation: false)
    }

    fileprivate func animationDidFinish() -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        guard activeAnimations > 0 else { return [] }
        activeAnimations -= 1
        return completionsIfReady(allowNoRegisteredAnimation: false)
    }

    func noRegisteredAnimationFallbackDidFire() -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        return completionsIfReady(allowNoRegisteredAnimation: true)
    }

    private func completionsIfReady(allowNoRegisteredAnimation: Bool) -> [() -> Void] {
        guard !completed,
              bodyFinished,
              (registeredAnimation || allowNoRegisteredAnimation),
              activeAnimations == 0 else {
            return []
        }
        completed = true
        // Removal callbacks are drained first so retained subtree teardown can
        // invalidate nodes before ordinary completion callbacks observe state.
        let removedCompletions = entries
            .filter { $0.criteria == .removed }
            .map(\.completion)
        let otherCompletions = entries
            .filter { $0.criteria != .removed }
            .map(\.completion)
        return removedCompletions + otherCompletions
    }
}

final class AnimationCompletionToken: @unchecked Sendable {
    private let observer: AnimationCompletionObserver
    private var finished = false

    init(observer: AnimationCompletionObserver) {
        self.observer = observer
    }

    func finish() -> [() -> Void] {
        guard !finished else { return [] }
        finished = true
        return observer.animationDidFinish()
    }
}

func enqueueAnimationCompletionActions(_ actions: [() -> Void]) {
    guard !actions.isEmpty else { return }
    let wrapped = actions.map { action in
        {
            AttributeGraph.withoutTracking(action)
        }
    }
    // Completion actions may trigger arbitrary view mutations. Queue them until
    // the graph leaves the current evaluation/draw pass when possible.
    if let graph = AttributeGraph.current {
        graph.actionOutbox.append(contentsOf: wrapped)
    } else {
        wrapped.forEach { $0() }
    }
}

private struct AnimationCompletionObserverBox: @unchecked Sendable {
    var observer: AnimationCompletionObserver
}

func enqueueNoRegisteredAnimationFallback(_ observer: AnimationCompletionObserver?) {
    guard let observer else { return }
    let box = AnimationCompletionObserverBox(observer: observer)
    DispatchQueue.main.async {
        enqueueAnimationCompletionActions(
            box.observer.noRegisteredAnimationFallbackDidFire()
        )
    }
}

extension Animation: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "Animation"
    }
    public var debugDescription: String {
        "Animation"
    }
    public var customMirror: Mirror {
        Mirror(self, children: ["base": box])
    }
}

extension Animation {
    public static let `default`: Animation = Animation(box: DefaultAnimationBox())
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
    public static func timingCurve(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double, duration: TimeInterval = 0.35) -> Animation {
        let curve = UnitCurve(c1x: p1x, c1y: p1y, c2x: p2x, c2y: p2y)
        return Animation(box: BezierAnimationBox(curve: curve, duration: max(0, duration)))
    }

    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation {
        timingCurve(curve.c1x, curve.c1y, curve.c2x, curve.c2y, duration: duration)
    }

    public func delay(_ delay: TimeInterval) -> Animation {
        Animation(box: DelayAnimationBox(base: box, delay: delay))
    }

    public func speed(_ speed: Double) -> Animation {
        Animation(box: SpeedAnimationBox(base: box, speed: speed))
    }

    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
        Animation(box: RepeatAnimationBox(base: box, repeatCount: repeatCount, autoreverses: autoreverses))
    }

    public func repeatForever(autoreverses: Bool = true) -> Animation {
        Animation(box: RepeatAnimationBox(base: box, repeatCount: nil, autoreverses: autoreverses))
    }
}

extension Animation {
    public static func spring(duration: TimeInterval = 0.5,
                              bounce: Double = 0.0,
                              blendDuration: Double = 0) -> Animation {
        spring(
            response: duration,
            dampingFraction: springDampingFraction(bounce: bounce),
            blendDuration: blendDuration
        )
    }

    public static func spring(response: Double = 0.5,
                              dampingFraction: Double = 0.825,
                              blendDuration: TimeInterval = 0) -> Animation {
        Animation(
            box: FluidSpringAnimationBox(
                response: response,
                dampingFraction: dampingFraction,
                blendDuration: blendDuration
            )
        )
    }

    public static var spring: Animation {
        spring(duration: 0.5, bounce: 0.0, blendDuration: 0)
    }

    public static func interactiveSpring(response: Double = 0.15,
                                         dampingFraction: Double = 0.86,
                                         blendDuration: TimeInterval = 0.25) -> Animation {
        Animation(
            box: FluidSpringAnimationBox(
                response: response,
                dampingFraction: dampingFraction,
                blendDuration: blendDuration
            )
        )
    }

    public static var interactiveSpring: Animation {
        interactiveSpring(duration: 0.15, extraBounce: 0.0, blendDuration: 0.25)
    }

    public static func interactiveSpring(duration: TimeInterval = 0.15,
                                         extraBounce: Double = 0.0,
                                         blendDuration: TimeInterval = 0.25) -> Animation {
        spring(
            duration: duration,
            bounce: 0.15 + extraBounce,
            blendDuration: blendDuration
        )
    }

    public static var smooth: Animation {
        smooth()
    }

    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: extraBounce)
    }

    public static var snappy: Animation {
        snappy()
    }

    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: 0.15 + extraBounce)
    }

    public static var bouncy: Animation {
        bouncy()
    }

    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: 0.3 + extraBounce)
    }

    public static func interpolatingSpring(mass: Double = 1.0,
                                           stiffness: Double,
                                           damping: Double,
                                           initialVelocity: Double = 0.0) -> Animation {
        Animation(
            box: SpringAnimationBox(
                mass: mass,
                stiffness: stiffness,
                damping: damping,
                initialVelocity: initialVelocity
            )
        )
    }

    public static func interpolatingSpring(duration: TimeInterval = 0.5,
                                           bounce: Double = 0.0,
                                           initialVelocity: Double = 0.0) -> Animation {
        let stiffness = pow(2 * .pi / max(duration, 0.001), 2)
        let damping = 2 * sqrt(stiffness) * springDampingFraction(bounce: bounce)
        return interpolatingSpring(
            mass: 1.0,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: initialVelocity
        )
    }

    public static var interpolatingSpring: Animation {
        interpolatingSpring()
    }

    private static func springDampingFraction(bounce: Double) -> Double {
        min(max(1 - bounce, 0.0), 1.0)
    }
}

public func withAnimation<Result>(
    _ animation: Animation? = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    try withTransaction(Transaction(animation: animation), body)
}

public func withAnimation<Result>(
    _ animation: Animation? = .default,
    completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
    _ body: () throws -> Result,
    completion: @escaping () -> Void
) rethrows -> Result {
    var transaction = Transaction(animation: animation)
    transaction.addAnimationCompletion(criteria: completionCriteria, completion)
    let result = try withTransaction(transaction, body)
    let observer = transaction.animationCompletionObserver
    enqueueAnimationCompletionActions(
        observer?.bodyDidFinish() ?? []
    )
    enqueueNoRegisteredAnimationFallback(observer)
    return result
}

private struct AnimationTransactionKey: TransactionKey {
    typealias Value = Animation?
    static var defaultValue: Animation? { nil }
}

private struct DisablesAnimationsTransactionKey: TransactionKey {
    typealias Value = Bool
    static var defaultValue: Bool { false }
}

private struct AnimationCompletionObserverTransactionKey: TransactionKey {
    typealias Value = AnimationCompletionObserver?
    static var defaultValue: AnimationCompletionObserver? { nil }

    static func _valuesEqual(_ lhs: AnimationCompletionObserver?, _ rhs: AnimationCompletionObserver?) -> Bool {
        lhs === rhs
    }
}

extension Transaction {
    public init(animation: Animation?) {
        plist = PropertyList()
        self.animation = animation
    }

    public var animation: Animation? {
        get { self[AnimationTransactionKey.self] }
        set { self[AnimationTransactionKey.self] = newValue }
    }

    var hasExplicitAnimationValue: Bool {
        plist.nonDefaultValue(forKey: TransactionKeyItem<AnimationTransactionKey>.self) != nil
    }

    public var disablesAnimations: Bool {
        get { self[DisablesAnimationsTransactionKey.self] }
        set { self[DisablesAnimationsTransactionKey.self] = newValue }
    }

    var animationCompletionObserver: AnimationCompletionObserver? {
        get { self[AnimationCompletionObserverTransactionKey.self] }
        set { self[AnimationCompletionObserverTransactionKey.self] = newValue }
    }

    public mutating func addAnimationCompletion(
        criteria: AnimationCompletionCriteria = .logicallyComplete,
        _ completion: @escaping () -> Void
    ) {
        if let observer = animationCompletionObserver {
            observer.add(criteria: criteria, completion: completion)
        } else {
            animationCompletionObserver = AnimationCompletionObserver(
                criteria: criteria,
                completion: completion
            )
        }
    }
}


public struct UnitCurve: Sendable, Hashable {
    let c1x, c1y, c2x, c2y: Double
    
    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(c1x: Double(startControlPoint.x),
                  c1y: Double(startControlPoint.y),
                  c2x: Double(endControlPoint.x),
                  c2y: Double(endControlPoint.y))
    }

    public func value(at progress: Double) -> Double {
        let timingFunction = TimingFunction(controlPoints: c1x, c1y, c2x, c2y)
        return timingFunction.solve(x: progress)
    }

    public func velocity(at progress: Double) -> Double {
        let timingFunction = TimingFunction(controlPoints: c1x, c1y, c2x, c2y)
        return timingFunction.derivative(x: progress)
    }

    public var inverse: UnitCurve {
        // Swap x and y coordinates to get inverse function
        UnitCurve(c1x: c1y, c1y: c1x, c2x: c2y, c2y: c2x)
    }
}

extension UnitCurve {
    /// Linear timing curve (no easing)
    public static let linear = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0, y: 0),
        endControlPoint: UnitPoint(x: 1, y: 1)
    )
    
    /// Ease-in timing curve (slow start)
    public static let easeIn = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.42, y: 0),
        endControlPoint: UnitPoint(x: 1, y: 1)
    )
    
    /// Ease-out timing curve (slow end)
    public static let easeOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0, y: 0),
        endControlPoint: UnitPoint(x: 0.58, y: 1)
    )
    
    /// Ease-in-out timing curve (slow start and end)
    public static let easeInOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.42, y: 0),
        endControlPoint: UnitPoint(x: 0.58, y: 1)
    )
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
        if x <= 0 || x >= 1 { return 0 }
        
        let t = solveCurveX(x, epsilon: epsilon)
        let dx = sampleDerivativeX(t)
        let dy = sampleDerivativeY(t)
        
        return dx != 0 ? dy / dx : 0
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
