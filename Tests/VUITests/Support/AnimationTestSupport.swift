import Foundation
@testable import VUI

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

    override func animationWasRemoved() -> [() -> Void] {
        lock.lock()
        removedStorage += 1
        lock.unlock()
        return []
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

    override func animationWasRemoved() -> [() -> Void] {
        recorder.record("\(label) removed")
        return []
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
