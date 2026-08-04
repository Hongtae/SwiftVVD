import Foundation
@testable import VUI

private func fluidSpringSettlingDuration<Value: VectorArithmetic>(
    response: TimeInterval,
    dampingFraction: Double,
    target: Value
) -> TimeInterval {
    let duration = max(0, response)
    guard duration > 0 else { return 0 }

    let step = 1.0 / 300.0
    let limit = max(duration * 12, 10)
    let stiffness = fluidSpringStiffness(response: response)
    var state = SpringState<Value>()
    var time: TimeInterval = 0
    while time <= limit {
        _ = integratedFluidSpringValue(
            target: target,
            dampingFraction: dampingFraction,
            stiffness: stiffness,
            time: time,
            state: &state
        )
        if isFluidSpringSettled(target: target, state: state) {
            return max(duration, time)
        }
        time += step
    }
    return limit
}

func finalizeAnimationCompletions(
    in transaction: Transaction,
    animation: Animation? = nil
) {
    _ = transaction
    _ = animation
    Transaction.dispatchPendingListeners()
}

extension AnimationBoxBase {
    var defaultDisplayFrameInterval: TimeInterval {
        1.0 / 60.0
    }

    // Test-only terminal sampling horizon. Runtime completion is owned by
    // CustomAnimation.animate returning nil, not by a parallel box property.
    var terminalSamplingHorizon: TimeInterval {
        terminalSamplingHorizon(for: Double(1))
    }

    func terminalSamplingHorizon<Value>(
        for value: Value
    ) -> TimeInterval where Value: VectorArithmetic {
        switch self {
        case is DefaultAnimationBox:
            return max(
                duration,
                fluidSpringSettlingDuration(
                    response: 0.5,
                    dampingFraction: 1,
                    target: value
                )
            )
        case let delay as DelayAnimationBox:
            return max(
                0,
                delay.base.terminalSamplingHorizon(for: value) + delay.delay
            )
        case let speed as SpeedAnimationBox:
            guard speed.speed > 0 else {
                return .infinity
            }
            return speed.base.terminalSamplingHorizon(for: value) / speed.speed
        case let repeatAnimation as RepeatAnimationBox:
            guard let repeatCount = repeatAnimation.repeatCount else {
                return .infinity
            }
            return repeatAnimation.base.terminalSamplingHorizon(for: value) *
                TimeInterval(max(repeatCount, 1))
        case let logical as LogicalCompletionAnimationBox:
            return logical.base.terminalSamplingHorizon(for: value)
        case let fluid as FluidSpringAnimationBox:
            let terminal = max(
                fluid.duration,
                fluidSpringSettlingDuration(
                    response: fluid.response,
                    dampingFraction: fluid.dampingFraction,
                    target: value
                )
            )
            return terminal
        case let spring as SpringAnimationBox:
            guard !spring.isImmediatelyComplete else {
                return 0
            }
            return SpringModel(
                mass: spring.mass,
                stiffness: spring.stiffness,
                damping: spring.damping,
                initialVelocity: spring.initialVelocity
            ).duration(epsilon: 0.001)
        default:
            return duration
        }
    }
}

struct UnitLinearAnimation: CustomAnimation {
    var duration: TimeInterval

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        guard time < duration else {
            context.isLogicallyComplete = true
            return nil
        }
        var output = value
        output.scale(by: max(time / duration, 0))
        return output
    }
}

final class AnimationVelocityRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: String) {
        lock.lock()
        storage.append(event)
        lock.unlock()
        if ProcessInfo.processInfo.environment["VUI_DEBUG_COMPLETIONS"] != nil {
            print("completion \(event)")
        }
    }
}

final class AnimationCompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: String) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

final class CountingAnimationListener: AnimationListener, @unchecked Sendable {
    private let lock = NSLock()
    private var addedStorage = 0
    private var removedStorage = 0

    var addedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return addedStorage
    }

    var removedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return removedStorage
    }

    override func animationWasAdded() {
        lock.lock()
        addedStorage += 1
        lock.unlock()
    }

    override func animationWasRemoved() {
        lock.lock()
        removedStorage += 1
        lock.unlock()
    }
}

final class RecordingAnimationListener: AnimationListener, @unchecked Sendable {
    private let label: String
    private let recorder: AnimationCompletionRecorder

    init(label: String, recorder: AnimationCompletionRecorder) {
        self.label = label
        self.recorder = recorder
    }

    override func animationWasAdded() {
        recorder.record("\(label) added")
    }

    override func animationWasRemoved() {
        recorder.record("\(label) removed")
    }
}

struct RecordingUnitAnimation: CustomAnimation {
    var label: String
    var duration: TimeInterval
    var recorder: AnimationCompletionRecorder

    static func == (lhs: RecordingUnitAnimation, rhs: RecordingUnitAnimation) -> Bool {
        lhs.label == rhs.label && lhs.duration == rhs.duration
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(duration)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        _ = context
        recorder.record("\(label) animate")
        guard time < duration else {
            context.isLogicallyComplete = true
            return nil
        }
        var output = value
        output.scale(by: max(time / duration, 0))
        return output
    }
}

struct RetargetBoundaryRecordingAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval
    var nilAt: TimeInterval
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: RetargetBoundaryRecordingAnimation,
        rhs: RetargetBoundaryRecordingAnimation
    ) -> Bool {
        lhs.label == rhs.label &&
            lhs.logicalAt == rhs.logicalAt &&
            lhs.nilAt == rhs.nilAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(logicalAt)
        hasher.combine(nilAt)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        if time >= logicalAt {
            context.isLogicallyComplete = true
        }
        recorder.recordSample(label: label, time: time, input: doubleValue(value))
        guard time < nilAt else {
            return nil
        }
        var output = value
        output.scale(by: max(time / nilAt, 0))
        return output
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = previous
        _ = value
        _ = time
        _ = context
        recorder.recordShouldMerge()
        return true
    }

    func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}

struct CombinedNilRetargetRecordingAnimation: CustomAnimation {
    var label: String
    var duration: TimeInterval
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: CombinedNilRetargetRecordingAnimation,
        rhs: CombinedNilRetargetRecordingAnimation
    ) -> Bool {
        lhs.label == rhs.label && lhs.duration == rhs.duration
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(duration)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        recorder.recordSample(label: label, time: time, input: doubleValue(value))
        guard time < duration else {
            context.isLogicallyComplete = true
            return nil
        }
        var output = value
        output.scale(by: max(time / duration, 0))
        return output
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = previous
        _ = value
        _ = time
        _ = context
        recorder.recordShouldMerge()
        return false
    }

    func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}

struct CombinedBoundaryRecordingAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval
    var nilAt: TimeInterval
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: CombinedBoundaryRecordingAnimation,
        rhs: CombinedBoundaryRecordingAnimation
    ) -> Bool {
        lhs.label == rhs.label &&
            lhs.logicalAt == rhs.logicalAt &&
            lhs.nilAt == rhs.nilAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(logicalAt)
        hasher.combine(nilAt)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        if time >= logicalAt {
            context.isLogicallyComplete = true
        }
        recorder.recordSample(label: label, time: time, input: doubleValue(value))
        guard time < nilAt else {
            return nil
        }
        var output = value
        output.scale(by: max(time / nilAt, 0))
        return output
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = previous
        _ = value
        _ = time
        _ = context
        recorder.recordShouldMerge()
        return false
    }

    func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}

final class CustomRetargetSampleRecorder: @unchecked Sendable {
    struct Sample {
        var label: String
        var time: TimeInterval
        var input: Double
    }

    private let lock = NSLock()
    private var sampleStorage: [Sample] = []
    private var shouldMergeStorage = 0

    var samples: [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return sampleStorage
    }

    var shouldMergeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return shouldMergeStorage
    }

    func recordSample(label: String, time: TimeInterval, input: Double) {
        lock.lock()
        sampleStorage.append(Sample(label: label, time: time, input: input))
        lock.unlock()
    }

    func recordShouldMerge() {
        lock.lock()
        shouldMergeStorage += 1
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        sampleStorage.removeAll()
        shouldMergeStorage = 0
        lock.unlock()
    }
}

func completionTransaction(
    animation: Animation?,
    label: String,
    recorder: AnimationCompletionRecorder
) -> Transaction {
    var transaction = Transaction(animation: animation)
    transaction.addAnimationCompletion(criteria: .removed) {
        recorder.record("\(label) removed")
    }
    transaction.addAnimationCompletion(criteria: .logicallyComplete) {
        recorder.record("\(label) logical")
    }
    return transaction
}

func velocityTrackingCompletionTransaction(
    label: String,
    recorder: AnimationCompletionRecorder
) -> Transaction {
    var transaction = completionTransaction(
        animation: nil,
        label: label,
        recorder: recorder
    )
    transaction.tracksVelocity = true
    return transaction
}

struct RecordingVelocityAnimation: CustomAnimation {
    var id: String
    var recorder: AnimationVelocityRecorder

    static func == (lhs: RecordingVelocityAnimation, rhs: RecordingVelocityAnimation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        _ = time
        _ = context
        recorder.record("animate:\(id)")
        return value
    }

    nonisolated func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        _ = value
        _ = time
        _ = context
        recorder.record("velocity:\(id)")
        return .zero
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = previous
        _ = value
        _ = time
        _ = context
        recorder.record("shouldMerge:\(id)")
        return false
    }
}
