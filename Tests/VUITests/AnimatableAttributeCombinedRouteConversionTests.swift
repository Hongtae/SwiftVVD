import XCTest
@testable import VUI

final class AnimatableAttributeCombinedRouteConversionTests: XCTestCase {
    func testFalseRetargetAppendsRepeatedSourceCustomEntriesToCombinedPreviousAnimation() throws {
        let recorder = CombinedRouteConversionRecorder()
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(initialValue: _OpacityEffect(opacity: 0))
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: customAnimation("old", recorder: recorder),
                label: "old",
                recorder: completionRecorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        sample(harness, at: [0.30])
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: customAnimation("second", recorder: recorder),
                label: "second",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        sample(harness, at: [0.60, 0.70])
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: logicalCompletionTransaction(
                animation: customAnimation("third", recorder: recorder),
                label: "third",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        let secondMerge = try XCTUnwrap(recorder.merge(role: "second"))
        XCTAssertFalse(secondMerge.previousIsDefaultCombining)
        XCTAssertTrue(
            secondMerge.previousBoxType.contains("CustomAnimationBox"),
            secondMerge.previousBoxType
        )

        let thirdMerge = try XCTUnwrap(recorder.merge(role: "third"))
        XCTAssertTrue(thirdMerge.previousIsDefaultCombining)
        XCTAssertEqual(thirdMerge.combinedCustomRoles, ["old", "second"])

        harness.setTime(0.80)
        let layeredSample = harness.currentValue().opacity
        XCTAssertTrue(recorder.sampledRoles.contains("old"))
        XCTAssertTrue(recorder.sampledRoles.contains("second"))
        XCTAssertTrue(recorder.sampledRoles.contains("third"))
        XCTAssertTrue(
            containsTripleOutputSum(
                layeredSample,
                recorder.samples(role: "old").compactMap(\.output),
                recorder.samples(role: "second").compactMap(\.output),
                recorder.samples(role: "third").compactMap(\.output)
            ),
            "sample=\(layeredSample), old=\(recorder.samples(role: "old")), " +
            "second=\(recorder.samples(role: "second")), third=\(recorder.samples(role: "third"))"
        )
    }

    func testFalseRetargetConvertsNonCustomSpringBaseToCombinedPreviousAnimation() throws {
        let recorder = CombinedRouteConversionRecorder()
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(initialValue: _OpacityEffect(opacity: 0))
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: Self.slowSpring,
                label: "spring",
                recorder: completionRecorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        sample(harness, at: [0.30])
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: customAnimation("second", recorder: recorder),
                label: "second",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        sample(harness, at: [0.90, 1.00])
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: logicalCompletionTransaction(
                animation: customAnimation("third", recorder: recorder),
                label: "third",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        let secondMerge = try XCTUnwrap(recorder.merge(role: "second"))
        XCTAssertFalse(secondMerge.previousIsDefaultCombining)
        XCTAssertTrue(
            secondMerge.previousBoxType.contains("SpringAnimation"),
            secondMerge.previousBoxType
        )

        let thirdMerge = try XCTUnwrap(recorder.merge(role: "third"))
        XCTAssertTrue(thirdMerge.previousIsDefaultCombining)
        XCTAssertTrue(
            thirdMerge.combinedEntryBoxTypes.contains { $0.contains("SpringAnimation") },
            thirdMerge.combinedEntryBoxTypes.joined(separator: ", ")
        )
        XCTAssertEqual(thirdMerge.combinedCustomRoles, ["second"])

        sample(harness, at: [1.10])
        XCTAssertTrue(recorder.sampledRoles.contains("second"))
        XCTAssertTrue(recorder.sampledRoles.contains("third"))
    }

    func testFalseRetargetConvertsNonMergedBaseLayerStackToCombinedPreviousAnimation() throws {
        let recorder = CombinedRouteConversionRecorder()
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(initialValue: _OpacityEffect(opacity: 0))
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 1.40),
                label: "linear",
                recorder: completionRecorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        sample(harness, at: [0.25])
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: Self.slowSpring,
                label: "spring",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        sample(harness, at: [0.90, 1.00])
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: logicalCompletionTransaction(
                animation: customAnimation("third", recorder: recorder),
                label: "third",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        sample(harness, at: [1.30, 1.40])
        harness.setSource(
            _OpacityEffect(opacity: -0.25),
            transaction: logicalCompletionTransaction(
                animation: customAnimation("fourth", recorder: recorder),
                label: "fourth",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        let thirdMerge = try XCTUnwrap(recorder.merge(role: "third"))
        XCTAssertTrue(thirdMerge.previousIsDefaultCombining)
        XCTAssertTrue(
            thirdMerge.combinedEntryBoxTypes.contains { $0.contains("BezierAnimation") },
            thirdMerge.combinedEntryBoxTypes.joined(separator: ", ")
        )
        XCTAssertTrue(
            thirdMerge.combinedEntryBoxTypes.contains { $0.contains("SpringAnimation") },
            thirdMerge.combinedEntryBoxTypes.joined(separator: ", ")
        )
        XCTAssertEqual(thirdMerge.combinedCustomRoles, [])

        let fourthMerge = try XCTUnwrap(recorder.merge(role: "fourth"))
        XCTAssertTrue(fourthMerge.previousIsDefaultCombining)
        XCTAssertTrue(
            fourthMerge.combinedEntryBoxTypes.contains { $0.contains("BezierAnimation") },
            fourthMerge.combinedEntryBoxTypes.joined(separator: ", ")
        )
        XCTAssertTrue(
            fourthMerge.combinedEntryBoxTypes.contains { $0.contains("SpringAnimation") },
            fourthMerge.combinedEntryBoxTypes.joined(separator: ", ")
        )
        XCTAssertEqual(fourthMerge.combinedCustomRoles, ["third"])

        sample(harness, at: [1.50])
        XCTAssertTrue(recorder.sampledRoles.contains("third"))
        XCTAssertTrue(recorder.sampledRoles.contains("fourth"))
    }

    func testTrueRetargetAfterFalseRetargetKeepsBaseLayerSamplingButUsesReplacementDelta() throws {
        let recorder = CombinedRouteConversionRecorder()
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(initialValue: _OpacityEffect(opacity: 0))
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: customAnimation(
                    "old",
                    duration: 0.80,
                    scale: 1,
                    shouldMerge: false,
                    recorder: recorder
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        sample(harness, at: [0.30])
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: customAnimation(
                    "second",
                    duration: 0.80,
                    scale: 2,
                    shouldMerge: false,
                    recorder: recorder
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        sample(harness, at: [0.60, 0.70])
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: logicalCompletionTransaction(
                animation: customAnimation(
                    "third",
                    duration: 0.80,
                    scale: 3,
                    shouldMerge: true,
                    recorder: recorder
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        let secondMerge = try XCTUnwrap(recorder.merge(role: "second"))
        XCTAssertFalse(secondMerge.previousIsDefaultCombining)
        XCTAssertEqual(secondMerge.value, 1, accuracy: 0.000_001)

        let thirdMerge = try XCTUnwrap(recorder.merge(role: "third"))
        XCTAssertTrue(thirdMerge.previousIsDefaultCombining)
        XCTAssertEqual(thirdMerge.combinedCustomRoles, ["old", "second"])
        XCTAssertEqual(thirdMerge.value, -0.5, accuracy: 0.000_001)

        harness.setTime(0.80)
        let layeredSample = harness.currentValue().opacity
        XCTAssertGreaterThan(layeredSample, 1.0)
        XCTAssertTrue(recorder.sampledRoles.contains("old"))
        XCTAssertTrue(recorder.sampledRoles.contains("second"))
        XCTAssertTrue(recorder.sampledRoles.contains("third"))

        let thirdSamples = recorder.samples(role: "third")
        XCTAssertTrue(
            thirdSamples.contains { abs($0.input - 0.75) <= 0.000_001 },
            thirdSamples.map(\.input).description
        )
        XCTAssertTrue(
            thirdSamples.contains { sample in
                guard let output = sample.output else {
                    return false
                }
                return abs(output - layeredSample) <= 0.000_001
            },
            "sample=\(layeredSample), thirdSamples=\(thirdSamples)"
        )
    }

    func testFalseRetargetComposesOldOutputWithFreshReplacementOutput() throws {
        let recorder = CombinedRouteConversionRecorder()
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(initialValue: _OpacityEffect(opacity: 0))
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: customAnimation(
                    "old",
                    duration: 0.80,
                    scale: 1,
                    shouldMerge: false,
                    recorder: recorder
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        let activationTime = 0.20
        let retargetTime = 0.30
        let sampleTime = 0.40
        let duration = 0.80
        harness.setTime(activationTime)
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.setTime(retargetTime)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: customAnimation(
                    "second",
                    duration: duration,
                    scale: 4,
                    shouldMerge: false,
                    recorder: recorder
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(sampleTime)
        let sample = harness.currentValue().opacity
        let oldOutputs = recorder.samples(role: "old").compactMap(\.output)
        let replacementSamples = recorder.samples(role: "second")
        XCTAssertTrue(
            oldOutputs.contains { oldOutput in
                replacementSamples.contains { replacementSample in
                    guard let replacementOutput = replacementSample.output else {
                        return false
                    }
                    return abs((oldOutput + replacementOutput) - sample) <= 0.000_001 &&
                        abs(replacementSample.input - (-0.5 - oldOutput)) <= 0.000_001
                }
            },
            "sample=\(sample), oldOutputs=\(oldOutputs), replacementSamples=\(replacementSamples)"
        )
    }

    func testTrueRetargetUsesReplacementOutputWithoutOldPresentationBase() throws {
        let recorder = CombinedRouteConversionRecorder()
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(initialValue: _OpacityEffect(opacity: 0))
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: customAnimation(
                    "old",
                    duration: 0.80,
                    scale: 1,
                    shouldMerge: true,
                    recorder: recorder
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        let activationTime = 0.20
        let retargetTime = 0.30
        let sampleTime = 0.40
        let duration = 0.80
        harness.setTime(activationTime)
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.setTime(retargetTime)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: customAnimation(
                    "second",
                    duration: duration,
                    scale: 4,
                    shouldMerge: true,
                    recorder: recorder
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(sampleTime)
        let sample = harness.currentValue().opacity
        let replacementSamples = recorder.samples(role: "second")
        XCTAssertTrue(
            replacementSamples.contains { replacementSample in
                guard let replacementOutput = replacementSample.output else {
                    return false
                }
                return abs(replacementOutput - sample) <= 0.000_001 &&
                    abs(replacementSample.input + 0.5) <= 0.000_001
            },
            "sample=\(sample), replacementSamples=\(replacementSamples)"
        )
        XCTAssertTrue(recorder.sampledRoles.contains("old"))
        XCTAssertTrue(recorder.sampledRoles.contains("second"))
        XCTAssertTrue(recorder.samples(role: "second").contains { abs($0.input + 0.5) <= 0.000_001 })
    }

    private static var slowSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 1.0,
            damping: 0.1,
            initialVelocity: 0.0
        )
    }

    private func customAnimation(
        _ role: String,
        duration: TimeInterval = 1.30,
        scale: Double = 1,
        shouldMerge: Bool = false,
        recorder: CombinedRouteConversionRecorder
    ) -> Animation {
        Animation(
            CombinedRouteConversionAnimation(
                role: role,
                duration: duration,
                scale: scale,
                shouldMergeResult: shouldMerge,
                recorder: recorder
            )
        )
    }

    private func sample(_ harness: AnimatableAttributeHarness, at times: [TimeInterval]) {
        for time in times {
            harness.setTime(time)
            _ = harness.currentValue()
        }
    }

    private func containsTripleOutputSum(
        _ value: Double,
        _ first: [Double],
        _ second: [Double],
        _ third: [Double],
        accuracy: Double = 0.000_001
    ) -> Bool {
        for lhs in first {
            for middle in second {
                for rhs in third where abs((lhs + middle + rhs) - value) <= accuracy {
                    return true
                }
            }
        }
        return false
    }

    private func logicalCompletionTransaction(
        animation: Animation?,
        label: String,
        recorder: AnimationCompletionRecorder
    ) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("\(label) logical")
        }
        return transaction
    }
}

private final class CombinedRouteConversionRecorder: @unchecked Sendable {
    struct Merge {
        var role: String
        var previousBoxType: String
        var previousIsDefaultCombining: Bool
        var combinedEntryBoxTypes: [String]
        var combinedCustomRoles: [String]
        var value: Double
    }

    struct Sample {
        var role: String
        var time: TimeInterval
        var input: Double
        var output: Double?
    }

    private let lock = NSLock()
    private var mergeStorage: [Merge] = []
    private var sampleStorage: Set<String> = []
    private var sampleRecords: [Sample] = []

    var sampledRoles: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return sampleStorage
    }

    func recordSample<Value>(
        role: String,
        value: Value,
        time: TimeInterval,
        duration: TimeInterval,
        scale: Double
    ) where Value: VectorArithmetic {
        let input = doubleValue(value)
        let output: Double? = time < duration ? input * max(time / duration, 0) * scale : nil
        lock.lock()
        sampleStorage.insert(role)
        sampleRecords.append(Sample(role: role, time: time, input: input, output: output))
        lock.unlock()
    }

    func recordMerge<Value>(role: String, previous: Animation, value: Value) where Value: VectorArithmetic {
        let defaultBox = previous.box as? CustomAnimationBox<DefaultCombiningAnimation>
        let merge = Merge(
            role: role,
            previousBoxType: String(describing: type(of: previous.box)),
            previousIsDefaultCombining: defaultBox != nil,
            combinedEntryBoxTypes: defaultBox?.base.entries.map {
                String(describing: type(of: $0.animation.box))
            } ?? [],
            combinedCustomRoles: defaultBox?.base.entries.compactMap {
                ($0.animation.box as? CustomAnimationBox<CombinedRouteConversionAnimation>)?.base.role
            } ?? [],
            value: doubleValue(value)
        )
        lock.lock()
        mergeStorage.append(merge)
        lock.unlock()
    }

    func merge(role: String) -> Merge? {
        lock.lock()
        defer { lock.unlock() }
        return mergeStorage.last { $0.role == role }
    }

    func samples(role: String) -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return sampleRecords.filter { $0.role == role }
    }

    private func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}

private struct CombinedRouteConversionAnimation: CustomAnimation {
    var role: String
    var duration: TimeInterval
    var scale: Double
    var shouldMergeResult: Bool
    var recorder: CombinedRouteConversionRecorder

    static func == (
        lhs: CombinedRouteConversionAnimation,
        rhs: CombinedRouteConversionAnimation
    ) -> Bool {
        lhs.role == rhs.role &&
            lhs.duration == rhs.duration &&
            lhs.scale == rhs.scale &&
            lhs.shouldMergeResult == rhs.shouldMergeResult
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(role)
        hasher.combine(duration)
        hasher.combine(scale)
        hasher.combine(shouldMergeResult)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        recorder.recordSample(
            role: role,
            value: value,
            time: time,
            duration: duration,
            scale: scale
        )
        guard time < duration else {
            context.isLogicallyComplete = true
            return nil
        }
        var output = value
        output.scale(by: max(time / duration, 0) * scale)
        return output
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = time
        _ = context
        recorder.recordMerge(role: role, previous: previous, value: value)
        return shouldMergeResult
    }
}
