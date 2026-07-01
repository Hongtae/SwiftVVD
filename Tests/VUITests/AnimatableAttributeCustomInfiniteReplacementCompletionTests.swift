import XCTest
@testable import VUI

final class AnimatableAttributeCustomInfiniteReplacementCompletionTests: XCTestCase {
    func testCustomNilToRepeatForeverDrainsOldLogicalAndKeepsRemovedPending() {
        assertCustomToInfiniteReplacement(
            label: "custom nil repeat",
            oldLogicalAt: nil,
            oldNilAt: 0.80,
            replacement: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterOldNil: ["old logical"]
        )
    }

    func testCustomLogicalToRepeatForeverDrainsOldLogicalBeforeNil() {
        assertCustomToInfiniteReplacement(
            label: "custom logical repeat",
            oldLogicalAt: 0.35,
            oldNilAt: 0.80,
            replacement: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            expectedEventsAfterOldLogical: ["old logical"],
            expectedEventsAfterOldNil: ["old logical"]
        )
    }

    func testCustomNilToSpeedZeroDrainsOldLogicalAndKeepsRemovedPending() {
        assertCustomToInfiniteReplacement(
            label: "custom nil speed zero",
            oldLogicalAt: nil,
            oldNilAt: 0.80,
            replacement: Animation.linear(duration: 0.40).speed(0),
            expectedEventsAfterOldLogical: nil,
            expectedEventsAfterOldNil: ["old logical"]
        )
    }

    private let retargetTime: TimeInterval = 0.20
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private var replacementActivationTime: TimeInterval {
        retargetTime + frameInterval
    }

    private func assertCustomToInfiniteReplacement(
        label: String,
        oldLogicalAt: TimeInterval?,
        oldNilAt: TimeInterval,
        replacement: Animation,
        expectedEventsAfterOldLogical: [String]?,
        expectedEventsAfterOldNil: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 1.0),
            transaction: completionTransaction(
                animation: Animation(
                    CustomInfiniteReplacementSourceAnimation(
                        label: "old",
                        logicalAt: oldLogicalAt,
                        nilAt: oldNilAt,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)

        sampleRunningAnimationBeforeRetarget(harness)
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: replacement,
                label: "infinite",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)

        if let oldLogicalAt, let expectedEventsAfterOldLogical {
            harness.setTime(retargetTime + oldLogicalAt + frameInterval)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                expectedEventsAfterOldLogical,
                label,
                file: file,
                line: line
            )
        }

        harness.setTime(retargetTime + oldNilAt + frameInterval)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            expectedEventsAfterOldNil,
            label,
            file: file,
            line: line
        )

        harness.setTime(retargetTime + oldNilAt + 2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            expectedEventsAfterOldNil,
            label,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            sampleRecorder.samples.map(\.time).max() ?? 0,
            oldNilAt,
            label,
            file: file,
            line: line
        )
    }

    private func sampleRunningAnimationBeforeRetarget(
        _ harness: AnimatableAttributeHarness
    ) {
        harness.setTime(retargetTime / 2.0)
        _ = harness.currentValue()
        harness.setTime(retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }

    private func activateReplacementAnimation(
        _ harness: AnimatableAttributeHarness
    ) {
        harness.setTime(replacementActivationTime)
        _ = harness.currentValue()
        harness.setTime(replacementActivationTime + frameInterval)
        _ = harness.currentValue()
        harness.setTime(replacementActivationTime + (frameInterval * 2.0))
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }
}

private struct CustomInfiniteReplacementSourceAnimation: CustomAnimation {
    var label: String
    var logicalAt: TimeInterval?
    var nilAt: TimeInterval
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: CustomInfiniteReplacementSourceAnimation,
        rhs: CustomInfiniteReplacementSourceAnimation
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
        if let logicalAt, time >= logicalAt {
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

    private func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}
