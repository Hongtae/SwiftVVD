import XCTest
@testable import VUI

final class AnimatableAttributeUnitCurveRetargetCriteriaTests: XCTestCase {
    func testCircularUnitCurveRetargetedToFiniteCurvesKeepsSampledCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.longCircular,
            oldRole: "firstCircular",
            replacementAnimation: .linear(duration: 0.15),
            replacementRole: "secondLinear",
            expectedEvents: [
                "firstCircularRemoved",
                "secondLinearRemoved",
                "secondLinearLogical",
                "firstCircularLogical",
            ],
            label: "circularToLinear"
        )
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.90),
            oldRole: "firstLinear",
            replacementAnimation: Self.shortCircular,
            replacementRole: "secondCircular",
            expectedEvents: [
                "firstLinearRemoved",
                "secondCircularRemoved",
                "secondCircularLogical",
                "firstLinearLogical",
            ],
            label: "linearToCircular"
        )
        assertRetargetOrder(
            oldAnimation: Self.longCircular,
            oldRole: "firstCircular",
            replacementAnimation: Self.shortCircular,
            replacementRole: "secondCircular",
            expectedEvents: [
                "firstCircularRemoved",
                "secondCircularRemoved",
                "secondCircularLogical",
                "firstCircularLogical",
            ],
            label: "circularToCircular"
        )
    }

    func testCircularUnitCurveRetargetedToDefaultAndResidualFamiliesKeepsSampledCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: Self.longCircular,
            oldRole: "firstCircular",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "secondDefaultLogical",
                "firstCircularLogical",
                "firstCircularRemoved",
                "secondDefaultRemoved",
            ],
            label: "circularToDefault"
        )
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: Self.shortCircular,
            replacementRole: "secondCircular",
            expectedEvents: [
                "firstDefaultRemoved",
                "secondCircularRemoved",
                "secondCircularLogical",
                "firstDefaultLogical",
            ],
            label: "defaultToCircular"
        )
        assertRetargetOrder(
            oldAnimation: Self.longCircular,
            oldRole: "firstCircular",
            replacementAnimation: Self.replacementFluidSpring,
            replacementRole: "secondSpring",
            expectedEvents: [
                "secondSpringLogical",
                "firstCircularRemoved",
                "secondSpringRemoved",
                "firstCircularLogical",
            ],
            label: "circularToSpring"
        )
        assertRetargetOrder(
            oldAnimation: Self.slowFluidSpring,
            oldRole: "firstSpring",
            replacementAnimation: Self.shortCircular,
            replacementRole: "secondCircular",
            expectedEvents: [
                "firstSpringRemoved",
                "secondCircularRemoved",
                "secondCircularLogical",
                "firstSpringLogical",
            ],
            label: "springToCircular"
        )
    }

    private func assertRetargetOrder(
        oldAnimation: Animation,
        oldRole: String,
        replacementAnimation: Animation,
        replacementRole: String,
        retargetTime: TimeInterval = 0.25,
        expectedEvents: [String],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let target = -0.5
        let frame = min(
            oldAnimation.box.defaultDisplayFrameInterval,
            replacementAnimation.box.defaultDisplayFrameInterval
        )

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: criteriaTransaction(
                animation: oldAnimation,
                role: oldRole,
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setTime(retargetTime)
        let retargetStartValue = harness.currentValue().opacity
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: target),
            transaction: criteriaTransaction(
                animation: replacementAnimation,
                role: replacementRole,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        let oldEnd = max(
            oldAnimation.box.duration,
            oldAnimation.box.presentationDuration(for: 1.0)
        )
        let replacementEnd = retargetTime + max(
            replacementAnimation.box.duration,
            replacementAnimation.box.presentationDuration(for: target - retargetStartValue)
        )
        let lastSampleTime = max(oldEnd, replacementEnd) + 3.0

        var sampleTime = retargetTime + frame
        while sampleTime <= lastSampleTime && recorder.events.count < expectedEvents.count {
            harness.setTime(sampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            sampleTime += frame
        }

        XCTAssertEqual(recorder.events, expectedEvents, label, file: file, line: line)
    }

    private func criteriaTransaction(
        animation: Animation,
        role: String,
        recorder: AnimationCompletionRecorder
    ) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("\(role)Logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("\(role)Removed")
        }
        return transaction
    }

    private static var longCircular: Animation {
        .timingCurve(.circularEaseInOut, duration: 0.90)
    }

    private static var shortCircular: Animation {
        .timingCurve(.circularEaseInOut, duration: 0.15)
    }

    private static var slowFluidSpring: Animation {
        .spring(response: 1.20, dampingFraction: 0.70, blendDuration: 0.0)
    }

    private static var replacementFluidSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.70, blendDuration: 0.0)
    }
}
