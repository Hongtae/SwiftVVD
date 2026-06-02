//
//  File: Animation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
class AnimationBoxBase: @unchecked Sendable {
    var duration: TimeInterval { 0 }

    func value(at progress: Double) -> Double {
        progress
    }
}

@usableFromInline
final class TimingCurveAnimationBox: AnimationBoxBase, @unchecked Sendable {
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

    private var entries: [Entry] = []
    private var activeAnimations: Int = 0
    private var bodyFinished = false
    private var registeredAnimation = false
    private var completed = false

    init(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        entries.append(Entry(criteria: criteria, completion: completion))
    }

    func add(criteria: AnimationCompletionCriteria, completion: @escaping () -> Void) {
        guard !completed else { return }
        entries.append(Entry(criteria: criteria, completion: completion))
    }

    func animationDidStart() -> AnimationCompletionToken? {
        guard !completed else { return nil }
        registeredAnimation = true
        activeAnimations += 1
        return AnimationCompletionToken(observer: self)
    }

    func bodyDidFinish() -> [() -> Void] {
        bodyFinished = true
        return completionsIfReady()
    }

    fileprivate func animationDidFinish() -> [() -> Void] {
        guard activeAnimations > 0 else { return [] }
        activeAnimations -= 1
        return completionsIfReady()
    }

    private func completionsIfReady() -> [() -> Void] {
        guard !completed,
              bodyFinished,
              registeredAnimation,
              activeAnimations == 0 else {
            return []
        }
        completed = true
        return entries.map(\.completion)
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
    if let graph = AttributeGraph.current {
        graph.actionOutbox.append(contentsOf: wrapped)
    } else {
        wrapped.forEach { $0() }
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
        fatalError()
    }
}

extension Animation {
    public static let `default`: Animation = .easeInOut
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
        return Animation(box: TimingCurveAnimationBox(curve: curve, duration: max(0, duration)))
    }

    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation {
        timingCurve(curve.c1x, curve.c1y, curve.c2x, curve.c2y, duration: duration)
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
    enqueueAnimationCompletionActions(
        transaction.animationCompletionObserver?.bodyDidFinish() ?? []
    )
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
