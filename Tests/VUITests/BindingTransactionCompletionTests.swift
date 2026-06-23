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
}
