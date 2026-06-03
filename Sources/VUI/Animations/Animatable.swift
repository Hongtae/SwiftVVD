//
//  File: Animatable.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}

public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic
    var animatableData: Self.AnimatableData { get set }

    static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs)
}

extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self { fatalError() }
}

extension Animatable where Self.AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData {
        @inlinable get { return EmptyAnimatableData() }
        @inlinable set {}
    }
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {
    }
}

extension Animatable {
    public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Self.self)._makeAnimatable called outside an active AttributeGraph context.")
        }
        let attr: Attribute<Self> = graph.makeStatefulRule(
            AnimatableAttribute(
                source: value._attribute,
                time: inputs.time,
                transaction: inputs.transaction
            )
        )
        value = _GraphValue(_attribute: attr)
    }
}

private struct AnimatableAttribute<AnimatedValue: Animatable>: StatefulRule {
    typealias Value = AnimatedValue

    var source: Attribute<AnimatedValue>
    var time: Attribute<Time>
    var transaction: Attribute<Transaction>

    var startValue: AnimatedValue?
    var targetValue: AnimatedValue?
    var currentValue: AnimatedValue?
    var startTime: Time = .zero
    var animation: Animation?
    // Each entry represents one transaction completion token waiting on this
    // animatable node. Retargeting extends older entries to the replacement
    // animation deadline while the newest token is inserted first.
    private var completionRecords: [CompletionRecord] = []

    private struct CompletionRecord {
        var token: AnimationCompletionToken
        var deadline: Time
    }

    init(
        source: Attribute<AnimatedValue>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>
    ) {
        self.source = source
        self.time = time
        self.transaction = transaction
    }

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("AnimatableAttribute.updateValue called outside an active AttributeGraph context.")
        }

        let target = source.value
        let inheritedTransaction = transaction.value
        let sourceTransaction = graph.transaction(for: source.identifier)
        let effectiveTransaction = sourceTransaction ?? inheritedTransaction

        if currentValue == nil {
            finishValue(with: target)
            return
        }

        let targetChanged = targetValue.map {
            $0.animatableData != target.animatableData
        } ?? true

        if targetChanged {
            guard let animation = effectiveTransaction.effectiveAnimation,
                  animation.box.duration > 0 else {
                finishValue(with: target)
                return
            }
            let now = time.value
            let start = interpolatedValue(at: now) ?? currentValue ?? target
            guard start.animatableData != target.animatableData else {
                finishValue(with: target)
                return
            }
            let deadline = now + animation.box.duration
            // Existing listeners stay attached to this node after a retarget and
            // complete at the replacement animation boundary.
            for index in completionRecords.indices {
                completionRecords[index].deadline = deadline
            }
            if let token = effectiveTransaction.animationCompletionObserver?.animationDidStart() {
                completionRecords.insert(CompletionRecord(token: token, deadline: deadline), at: 0)
            }
            startValue = start
            targetValue = target
            currentValue = start
            startTime = now
            self.animation = animation
        }

        guard let animation,
              let startValue,
              let targetValue else {
            finishValue(with: target)
            return
        }

        let now = time.value
        let rawProgress = min(
            max((now.seconds - startTime.seconds) / animation.box.duration, 0),
            1
        )
        if rawProgress >= 1 {
            finishAnimation(with: targetValue, at: now)
            return
        }

        let progress = animation.box.value(at: rawProgress)
        let output = interpolate(from: startValue, to: targetValue, progress: progress)
        currentValue = output
        AttributeGraph.setStatefulOutput(output)
    }

    mutating func destroy() {
        // Node removal is the last chance to finish listeners that were waiting
        // on this animatable value but no longer have a live output node.
        let completions = finishAllCompletionRecords()
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func finishValue(with value: AnimatedValue) {
        startValue = nil
        targetValue = value
        currentValue = value
        animation = nil
        AttributeGraph.setStatefulOutput(value)
        guard !completionRecords.isEmpty else { return }
        let now = time.value
        let completions = finishDueCompletionRecords(at: now)
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func finishAnimation(with value: AnimatedValue, at now: Time) {
        startValue = nil
        targetValue = value
        currentValue = value
        animation = nil
        AttributeGraph.setStatefulOutput(value)
        let completions = finishDueCompletionRecords(at: now)
        enqueueAnimationCompletionActions(completions)
    }

    private mutating func finishDueCompletionRecords(at now: Time) -> [() -> Void] {
        var readyCompletions: [() -> Void] = []
        var pendingRecords: [CompletionRecord] = []
        for record in completionRecords {
            if record.deadline < now || record.deadline == now {
                readyCompletions.append(contentsOf: record.token.finish())
            } else {
                pendingRecords.append(record)
            }
        }
        completionRecords = pendingRecords
        return readyCompletions
    }

    private mutating func finishAllCompletionRecords() -> [() -> Void] {
        let records = completionRecords
        completionRecords.removeAll()
        return records.flatMap { $0.token.finish() }
    }

    private func interpolatedValue(at time: Time) -> AnimatedValue? {
        guard let animation,
              let startValue,
              let targetValue else {
            return currentValue
        }
        let rawProgress = min(
            max((time.seconds - startTime.seconds) / animation.box.duration, 0),
            1
        )
        return interpolate(
            from: startValue,
            to: targetValue,
            progress: animation.box.value(at: rawProgress)
        )
    }

    private func interpolate(
        from start: AnimatedValue,
        to target: AnimatedValue,
        progress: Double
    ) -> AnimatedValue {
        var data = target.animatableData
        data -= start.animatableData
        data.scale(by: progress)
        data += start.animatableData

        var output = target
        output.animatableData = data
        return output
    }
}

extension View where Self: Animatable {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError()
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError()
    }
}

public struct AnimatablePair<First, Second>: VectorArithmetic where First: VectorArithmetic, Second: VectorArithmetic {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    @inlinable subscript() -> (First, Second) {
      get { return (first, second) }
      set { (first, second) = newValue }
    }

    public static var zero: AnimatablePair<First, Second> {
        return .init(First.zero, Second.zero)
    }

    public static func += (lhs: inout AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) {
        lhs.first += rhs.first
        lhs.second += rhs.second
    }

    public static func -= (lhs: inout AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) {
        lhs.first -= rhs.first
        lhs.second -= rhs.second
    }

    public static func + (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
        return .init(lhs.first + rhs.first, lhs.second + rhs.second)
    }

    public static func - (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
        return .init(lhs.first - rhs.first, lhs.second - rhs.second)
    }

    public mutating func scale(by rhs: Double) {
        first.scale(by: rhs)
        second.scale(by: rhs)
    }

    public var magnitudeSquared: Double {
        return first.magnitudeSquared + second.magnitudeSquared
    }
}

extension AnimatablePair: Equatable {
    public static func == (a: AnimatablePair<First, Second>, b: AnimatablePair<First, Second>) -> Bool {
        return a.first == b.first && a.second == b.second
    }
}

extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {
}

private extension VectorArithmetic {
    @inline(__always)
    func add(_ rhs: any VectorArithmetic) -> Self {
        assert(rhs is Self)
        return self + (rhs as! Self)
    }
    @inline(__always)
    func subtract(_ rhs: any VectorArithmetic) -> Self {
        assert(rhs is Self)
        return self - (rhs as! Self)
    }
    @inline(__always)
    func isEqual(to rhs: any VectorArithmetic) -> Bool {
        if let v = rhs as? Self {
            return self == v
        }
        return false
    }
}

public struct _AnyAnimatableData: VectorArithmetic {

    private struct _Zero: VectorArithmetic {
        static func += (_: inout Self, _: Self)     { fatalError() }
        static func -= (_: inout Self, _: Self)     { fatalError() }
        static func + (_: Self, _: Self) -> Self    { fatalError() }
        static func - (_: Self, _: Self) -> Self    { fatalError() }
        static func == (_: Self, _: Self) -> Bool   { fatalError() }
        static var zero: Self { Self() }
        func scale(by: Double) { }
        var magnitudeSquared: Double { 0 }
    }

    var value: any VectorArithmetic

    init(_ value: any VectorArithmetic) {
        self.value = value
    }

    public static var zero: Self {
        Self(_Zero.zero)
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    public static func -= (lhs: inout Self, rhs: Self) {
        lhs = lhs - rhs
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        if lhs.value is _Zero { return Self(rhs) }
        if rhs.value is _Zero { return Self(lhs) }
        return Self(lhs.add(rhs))
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        if lhs.value is _Zero {
            var v = rhs.value
            v.scale(by: -1)
            return Self(v)
        }
        if rhs.value is _Zero { return Self(lhs) }
        return Self(lhs.subtract(rhs))
    }

    public mutating func scale(by rhs: Double) {
        self.value.scale(by: rhs)
    }

    public var magnitudeSquared: Double {
        self.value.magnitudeSquared
    }

    public static func == (a: Self, b: Self) -> Bool {
        if a.value is _Zero { return b.magnitudeSquared == 0 }
        if b.value is _Zero { return a.magnitudeSquared == 0 }
        return a.value.isEqual(to: b.value)
    }
}
