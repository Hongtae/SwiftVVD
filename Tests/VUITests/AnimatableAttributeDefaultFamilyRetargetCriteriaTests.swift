import XCTest
@testable import VUI

final class AnimatableAttributeDefaultFamilyRetargetCriteriaTests: XCTestCase {
    func testFiniteCurvesAndWrappersRetargetedToDefaultKeepCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.90),
            oldRole: "firstLinear",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "secondDefaultLogical",
                "firstLinearLogical",
                "firstLinearRemoved",
                "secondDefaultRemoved",
            ],
            label: "linearToDefault"
        )
        assertRetargetOrder(
            oldAnimation: Self.longBezier,
            oldRole: "firstBezier",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "secondDefaultLogical",
                "firstBezierLogical",
                "firstBezierRemoved",
                "secondDefaultRemoved",
            ],
            label: "bezierToDefault"
        )
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.65).delay(0.25),
            oldRole: "firstDelay",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "secondDefaultLogical",
                "firstDelayLogical",
                "firstDelayRemoved",
                "secondDefaultRemoved",
            ],
            label: "delayToDefault"
        )
        assertRetargetOrder(
            oldAnimation: .linear(duration: 1.20).speed(2.0),
            oldRole: "firstSpeed",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "firstSpeedLogical",
                "secondDefaultLogical",
                "firstSpeedRemoved",
                "secondDefaultRemoved",
            ],
            label: "speedToDefault"
        )
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.30).repeatCount(3, autoreverses: false),
            oldRole: "firstRepeat",
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "secondDefaultLogical",
                "firstRepeatRemoved",
                "secondDefaultRemoved",
                "firstRepeatLogical",
            ],
            label: "repeatToDefault"
        )
    }

    func testDefaultRetargetedToFiniteCurvesAndWrappersClampsCriteriaOrder() {
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: .linear(duration: 0.15),
            replacementRole: "secondLinear",
            expectedEvents: [
                "firstDefaultRemoved",
                "secondLinearRemoved",
                "secondLinearLogical",
                "firstDefaultLogical",
            ],
            label: "defaultToLinear"
        )
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: Self.shortBezier,
            replacementRole: "secondBezier",
            expectedEvents: [
                "firstDefaultRemoved",
                "secondBezierRemoved",
                "secondBezierLogical",
                "firstDefaultLogical",
            ],
            label: "defaultToBezier"
        )
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: .linear(duration: 0.10).delay(0.10),
            replacementRole: "secondDelay",
            expectedEvents: [
                "firstDefaultRemoved",
                "secondDelayRemoved",
                "secondDelayLogical",
                "firstDefaultLogical",
            ],
            label: "defaultToDelay"
        )
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: .linear(duration: 0.30).speed(2.0),
            replacementRole: "secondSpeed",
            expectedEvents: [
                "firstDefaultRemoved",
                "secondSpeedRemoved",
                "secondSpeedLogical",
                "firstDefaultLogical",
            ],
            label: "defaultToSpeed"
        )
        assertRetargetOrder(
            oldAnimation: .default,
            oldRole: "firstDefault",
            replacementAnimation: .linear(duration: 0.075).repeatCount(2, autoreverses: false),
            replacementRole: "secondRepeat",
            expectedEvents: [
                "firstDefaultRemoved",
                "secondRepeatRemoved",
                "secondRepeatLogical",
                "firstDefaultLogical",
            ],
            label: "defaultToRepeat"
        )
    }

    func testFiniteRepeatSingleCriteriaRetargetedToDefaultGroupsAtDefaultBoundary() {
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.30).repeatCount(3, autoreverses: false),
            oldRole: "firstRepeat",
            oldCriteria: [.logical],
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "secondDefaultLogical",
                "secondDefaultRemoved",
                "firstRepeatLogical",
            ],
            label: "repeatLogicalOnlyToDefault"
        )
        assertRetargetOrder(
            oldAnimation: .linear(duration: 0.30).repeatCount(3, autoreverses: false),
            oldRole: "firstRepeat",
            oldCriteria: [.removed],
            replacementAnimation: .default,
            replacementRole: "secondDefault",
            expectedEvents: [
                "secondDefaultLogical",
                "firstRepeatRemoved",
                "secondDefaultRemoved",
            ],
            label: "repeatRemovedOnlyToDefault"
        )
    }

    private func assertRetargetOrder(
        oldAnimation: Animation,
        oldRole: String,
        oldCriteria: [CompletionRegistration] = [.logical, .removed],
        replacementAnimation: Animation,
        replacementRole: String,
        replacementCriteria: [CompletionRegistration] = [.logical, .removed],
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
                criteria: oldCriteria,
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
                criteria: replacementCriteria,
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
        criteria: [CompletionRegistration],
        recorder: AnimationCompletionRecorder
    ) -> Transaction {
        var transaction = Transaction(animation: animation)
        for registration in criteria {
            transaction.addAnimationCompletion(criteria: registration.criteria) {
                recorder.record("\(role)\(registration.suffix)")
            }
        }
        return transaction
    }

    private enum CompletionRegistration {
        case logical
        case removed

        var criteria: AnimationCompletionCriteria {
            switch self {
            case .logical:
                return .logicallyComplete
            case .removed:
                return .removed
            }
        }

        var suffix: String {
            switch self {
            case .logical:
                return "Logical"
            case .removed:
                return "Removed"
            }
        }
    }

    private static var longBezier: Animation {
        .timingCurve(0.25, 0.10, 0.25, 1.0, duration: 0.90)
    }

    private static var shortBezier: Animation {
        .timingCurve(0.42, 0.0, 0.58, 1.0, duration: 0.15)
    }
}
