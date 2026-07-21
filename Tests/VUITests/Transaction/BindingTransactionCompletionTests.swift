import XCTest
@testable import VUI

final class BindingTransactionCompletionTests: XCTestCase {
    func testBindingLocalTransactionConsumedByAnimatableWriteWaitsForRegisteredBoundary() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        let recorder = AnimationCompletionRecorder()
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("binding logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("binding removed")
        }

        harness.setSourceThroughBinding(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        XCTAssertEqual(recorder.events, [])

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        for time in stride(from: 0.6, through: 8.0, by: 0.6) {
            harness.setTime(time)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            if recorder.events.isEmpty {
                continue
            }
            XCTAssertEqual(recorder.events, ["binding removed", "binding logical"])
            return
        }

        harness.setTime(12.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["binding removed", "binding logical"])
    }

    func testDynamicMemberBindingLocalTransactionConsumedByAnimatableWriteWaitsForRegisteredBoundary() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        let recorder = AnimationCompletionRecorder()
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("dynamic logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("dynamic removed")
        }

        harness.setSourceThroughDynamicMemberBinding(1, transaction: transaction)
        XCTAssertEqual(recorder.events, [])

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        for time in stride(from: 1.0 / 60.0, through: 0.45, by: 1.0 / 60.0) {
            harness.setTime(time)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            if recorder.events.isEmpty {
                continue
            }
            XCTAssertEqual(recorder.events, ["dynamic removed", "dynamic logical"])
            harness.setTime(0.60)
            XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, ["dynamic removed", "dynamic logical"])
            return
        }

        harness.setTime(0.60)
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["dynamic removed", "dynamic logical"])
    }

    func testCollectionElementBindingLocalTransactionIsIgnoredByAnimatableWrite() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        let recorder = AnimationCompletionRecorder()
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("collection local removed")
        }

        harness.setSourceThroughCollectionElementBinding(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["collection local removed"])

        harness.setTime(0.30)
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["collection local removed"])
    }

    func testCollectionDynamicMemberBindingLocalTransactionIsIgnoredByAnimatableWrite() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        let recorder = AnimationCompletionRecorder()
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("collection member local removed")
        }

        harness.setSourceThroughCollectionMemberBinding(1, transaction: transaction)
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["collection member local removed"])

        harness.setTime(0.30)
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["collection member local removed"])
    }
}
