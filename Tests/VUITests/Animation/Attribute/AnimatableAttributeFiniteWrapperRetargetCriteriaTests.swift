import XCTest
@testable import VUI

final class AnimatableAttributeFiniteWrapperRetargetCriteriaTests: XCTestCase {
    func testFiniteWrappersRetargetedToFiniteWrappersGroupAtReplacementBoundary() {
        assertFiniteRetargetOrder(
            oldAnimation: .linear(duration: 0.50).delay(0.30),
            replacementAnimation: .linear(duration: 0.30).speed(2.0),
            label: "delayToSpeed"
        )
        assertFiniteRetargetOrder(
            oldAnimation: .linear(duration: 0.80).speed(0.5),
            replacementAnimation: .linear(duration: 0.20).repeatCount(2, autoreverses: false),
            label: "speedToRepeat"
        )
        assertFiniteRetargetOrder(
            oldAnimation: .linear(duration: 0.25).repeatCount(3, autoreverses: false),
            replacementAnimation: .linear(duration: 0.20).delay(0.20),
            label: "repeatToDelay"
        )
    }

    func testPlainFiniteOldRetargetedToFiniteWrappersGroupsAtReplacementBoundary() {
        assertFiniteRetargetOrder(
            oldAnimation: .timingCurve(0.35, 0.0, 0.65, 1.0, duration: 0.90),
            replacementAnimation: .linear(duration: 0.20).delay(0.20),
            label: "bezierToDelay"
        )
        assertFiniteRetargetOrder(
            oldAnimation: .easeOut(duration: 0.90),
            replacementAnimation: .linear(duration: 0.20).repeatCount(2, autoreverses: false),
            label: "easeToRepeat"
        )
        assertFiniteRetargetOrder(
            oldAnimation: .timingCurve(Self.cubicUnitCurve, duration: 0.90),
            replacementAnimation: .linear(duration: 0.30).speed(2.0),
            label: "cubicToSpeed"
        )
        assertFiniteRetargetOrder(
            oldAnimation: .linear(duration: 0.90),
            replacementAnimation: .linear(duration: 0.30).speed(2.0),
            label: "linearToSpeed"
        )
        assertFiniteRetargetOrder(
            oldAnimation: .linear(duration: 0.90),
            replacementAnimation: .linear(duration: 0.20).repeatCount(2, autoreverses: false),
            label: "linearToRepeat"
        )
    }

    func testFiniteWrappersRetargetedToPlainFiniteGroupsAtReplacementBoundary() {
        assertFiniteRetargetOrder(
            oldAnimation: .linear(duration: 0.50).delay(0.30),
            replacementAnimation: .linear(duration: 0.35),
            label: "delayToLinear"
        )
        assertFiniteRetargetOrder(
            oldAnimation: .linear(duration: 0.80).speed(0.5),
            replacementAnimation: .linear(duration: 0.35),
            label: "speedToLinear"
        )
        assertFiniteRetargetOrder(
            oldAnimation: .linear(duration: 0.25).repeatCount(3, autoreverses: false),
            replacementAnimation: .linear(duration: 0.35),
            label: "repeatToLinear"
        )
    }

    func testFiniteWrapperNilRetargetPreservesOldDeadline() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let oldAnimation = Animation.linear(duration: 0.50).delay(0.30)
        let retargetTime = 0.20
        let frame = oldAnimation.box.defaultDisplayFrameInterval

        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: "old",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.advanceTime(to: retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        let nilTransaction = completionTransaction(
            animation: nil,
            label: "replacement",
            recorder: recorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 2))
        }
        _ = harness.currentValue()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed",
                "replacement logical",
            ]
        )

        harness.advanceTime(to: oldAnimation.box.duration - frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed",
                "replacement logical",
            ]
        )

        harness.advanceTime(to: oldAnimation.box.duration + frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed",
                "replacement logical",
                "old removed",
                "old logical",
            ]
        )
    }

    private func assertFiniteRetargetOrder(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.20
        let replacementBoundary = retargetTime + replacementAnimation.box.duration
        let frame = replacementAnimation.box.defaultDisplayFrameInterval

        XCTAssertEqual(harness.currentValue().opacity, 0, label, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: "old",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.advanceTime(to: retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: completionTransaction(
                animation: replacementAnimation,
                label: "replacement",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.advanceTime(to: replacementBoundary - frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.advanceTime(to: replacementBoundary + max(0.10, frame))
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ],
            label,
            file: file,
            line: line
        )
    }

    private static var cubicUnitCurve: UnitCurve {
        UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.18, y: 0.07),
            endControlPoint: UnitPoint(x: 0.82, y: 0.96)
        )
    }
}
