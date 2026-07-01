import XCTest
@testable import VUI

final class AnimatableAttributeBuiltInFamilyRetargetCompletionTests: XCTestCase {
    func testLinearRetargetedToDirectSpringCompletesReplacementBeforeOldLinear() {
        assertOrderedLogicalRetarget(
            oldAnimation: .linear(duration: 1.00),
            replacementAnimation: Self.interpolatingSpring,
            retargetTime: 0.25,
            label: "linearToInterpolating",
            firstBoundary: .replacement,
            secondBoundary: .old
        )
    }

    func testDirectSpringRetargetedToLinearCompletesOldSpringBeforeReplacementLinear() {
        assertOrderedLogicalRetarget(
            oldAnimation: Self.interpolatingSpring,
            replacementAnimation: .linear(duration: 0.50),
            retargetTime: 0.25,
            label: "interpolatingToLinear",
            firstBoundary: .old,
            secondBoundary: .replacement
        )
    }

    func testFluidSpringRetargetedToDirectSpringCompletesOldFluidBeforeReplacementSpring() {
        assertOrderedLogicalRetarget(
            oldAnimation: Self.slowFluidSpring,
            replacementAnimation: Self.interpolatingSpring,
            retargetTime: 0.25,
            label: "fluidToInterpolating",
            firstBoundary: .old,
            secondBoundary: .replacement
        )
    }

    func testDirectSpringRetargetedToFluidSpringCompletesReplacementFluidBeforeOldSpring() {
        assertOrderedLogicalRetarget(
            oldAnimation: Self.interpolatingSpring,
            replacementAnimation: Self.fastFluidSpring,
            retargetTime: 0.25,
            label: "interpolatingToFluid",
            firstBoundary: .replacement,
            secondBoundary: .old
        )
    }

    func testLongFluidSpringRetargetedToShortLinearGroupsAtReplacementBoundary() {
        assertGroupedLogicalRetarget(
            oldAnimation: Self.longFluidSpring,
            replacementAnimation: .linear(duration: 0.30),
            retargetTime: 0.25,
            label: "fluidLongToShortLinear"
        )
    }

    func testRepeatForeverRetargetedToLinearGroupsAtReplacementBoundary() {
        assertGroupedLogicalRetarget(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            replacementAnimation: .linear(duration: 0.30),
            retargetTime: 0.45,
            label: "repeatForeverToLinear"
        )
    }

    func testSpeedZeroRetargetedToLinearGroupsAtReplacementBoundary() {
        assertGroupedLogicalRetarget(
            oldAnimation: Animation.linear(duration: 0.40).speed(0.0),
            replacementAnimation: .linear(duration: 0.30),
            retargetTime: 0.45,
            label: "speedZeroToLinear"
        )
    }

    private enum Boundary {
        case old
        case replacement
    }

    private func assertOrderedLogicalRetarget(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        retargetTime: TimeInterval,
        label: String,
        firstBoundary: Boundary,
        secondBoundary: Boundary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = makeRetargetedHarness(
            oldAnimation: oldAnimation,
            replacementAnimation: replacementAnimation,
            retargetTime: retargetTime,
            recorder: recorder,
            file: file,
            line: line
        )
        let frame = replacementAnimation.box.defaultDisplayFrameInterval
        let oldBoundary = oldAnimation.box.duration
        let replacementBoundary = retargetTime + replacementAnimation.box.duration
        let firstTime = firstBoundary == .old ? oldBoundary : replacementBoundary
        let secondTime = secondBoundary == .old ? oldBoundary : replacementBoundary
        let firstEvent = firstBoundary == .old ? "old logical" : "replacement logical"
        let secondEvent = secondBoundary == .old ? "old logical" : "replacement logical"

        XCTAssertLessThan(firstTime, secondTime, label, file: file, line: line)
        harness.setTime(firstTime + frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [firstEvent], label, file: file, line: line)

        harness.setTime(secondTime + frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [firstEvent, secondEvent], label, file: file, line: line)
    }

    private func assertGroupedLogicalRetarget(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        retargetTime: TimeInterval,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = makeRetargetedHarness(
            oldAnimation: oldAnimation,
            replacementAnimation: replacementAnimation,
            retargetTime: retargetTime,
            recorder: recorder,
            file: file,
            line: line
        )
        let frame = replacementAnimation.box.defaultDisplayFrameInterval
        let replacementBoundary = retargetTime + replacementAnimation.box.duration

        harness.setTime(replacementBoundary - frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], label, file: file, line: line)

        harness.setTime(replacementBoundary + frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(Set(recorder.events), ["old logical", "replacement logical"], label, file: file, line: line)
        XCTAssertEqual(recorder.events.count, 2, label, file: file, line: line)
    }

    private func makeRetargetedHarness(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        retargetTime: TimeInterval,
        recorder: AnimationCompletionRecorder,
        file: StaticString,
        line: UInt
    ) -> AnimatableAttributeHarness {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: oldAnimation,
                label: "old",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.finalizeTransactionBody()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: replacementAnimation,
                label: "replacement",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)
        return harness
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

    private static var interpolatingSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 90.0,
            damping: 12.0,
            initialVelocity: 0.0
        )
    }

    private static var fastFluidSpring: Animation {
        .spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }

    private static var slowFluidSpring: Animation {
        .spring(
            response: 0.80,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }

    private static var longFluidSpring: Animation {
        .spring(
            response: 1.20,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }
}
