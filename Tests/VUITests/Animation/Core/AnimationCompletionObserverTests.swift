import XCTest
@testable import VUI

final class AnimationCompletionListenerTests: XCTestCase {
    func testAllFinishedFinalizesImmediatelyWithoutAnimations() {
        var counts: [Int] = []
        let listener = AllFinishedListener { info in
            counts.append(info.completedCount)
        }

        listener.finalizeTransaction()
        listener.finalizeTransaction()

        XCTAssertEqual(counts, [0])
    }

    func testAllFinishedWaitsForEveryActiveAnimation() {
        var counts: [Int] = []
        let listener = AllFinishedListener { info in
            counts.append(info.completedCount)
        }

        listener.animationWasAdded()
        listener.animationWasAdded()
        listener.finalizeTransaction()
        XCTAssertEqual(counts, [])

        listener.animationWasRemoved()
        XCTAssertEqual(counts, [])

        listener.animationWasRemoved()
        XCTAssertEqual(counts, [2])
    }

    func testAllFinishedDoesNotRefireAfterLateRegistration() {
        var counts: [Int] = []
        let listener = AllFinishedListener { info in
            counts.append(info.completedCount)
        }

        listener.finalizeTransaction()
        listener.animationWasAdded()
        listener.animationWasRemoved()

        XCTAssertEqual(counts, [0])
    }

    func testAllFinishedDeinitFinalizesUnregisteredListener() {
        var counts: [Int] = []
        do {
            let listener = AllFinishedListener { info in
                counts.append(info.completedCount)
            }
            withExtendedLifetime(listener) {}
        }

        XCTAssertEqual(counts, [0])
    }

    func testHostedTokenWaitsForOrdinaryAnimationsBeforeReportingReadiness() {
        var counts: [Int] = []
        var readinessCount = 0
        let listener = AllFinishedListener { info in
            counts.append(info.completedCount)
        }
        let token = AnimationCompletionToken(
            listener: listener,
            usesHostedLifecycle: true
        )

        listener.animationWasAdded()
        token.start()
        token.observeHostedAnimationReadiness {
            readinessCount += 1
        }
        listener.finalizeTransaction()

        XCTAssertFalse(token.hasOnlyHostedAnimations)
        XCTAssertEqual(readinessCount, 0)
        XCTAssertEqual(counts, [])

        listener.animationWasRemoved()
        XCTAssertTrue(token.hasOnlyHostedAnimations)
        XCTAssertEqual(readinessCount, 1)
        XCTAssertEqual(counts, [])

        token.finish()
        XCTAssertEqual(counts, [2])
    }

    func testEachCompletionRegistrationOwnsIndependentListener() throws {
        var events: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("first")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("second")
        }

        let listener = try XCTUnwrap(transaction.animationLogicalListener)
        listener.animationWasAdded()
        listener.finalizeTransaction()
        XCTAssertEqual(events, [])

        listener.animationWasRemoved()
        XCTAssertEqual(events, ["first", "second"])
    }

    func testCombinedListenerForwardsRegularBeforeLogical() throws {
        var events: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("removed")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical")
        }

        let listener = try XCTUnwrap(transaction.combinedAnimationListener)
        listener.animationWasAdded()
        listener.animationWasRemoved()

        XCTAssertEqual(events, ["removed", "logical"])
    }

    func testPendingDispatchFinalizesRetainedTransaction() {
        var events: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion {
            events.append("completion")
        }

        XCTAssertEqual(events, [])
        Transaction.dispatchPendingListeners()
        XCTAssertEqual(events, ["completion"])
        withExtendedLifetime(transaction) {}
    }

    func testDroppedTransactionFinalizesAtListenerLifetimeBoundary() {
        var events: [String] = []
        do {
            var transaction = Transaction()
            transaction.addAnimationCompletion {
                events.append("completion")
            }
        }

        XCTAssertEqual(events, ["completion"])
    }

    func testWithAnimationWithoutMutationCompletesBeforeReturn() {
        var events: [String] = []

        withAnimation(.linear(duration: 1), completionCriteria: .removed) {
            events.append("body")
        } completion: {
            events.append("completion")
        }

        XCTAssertEqual(events, ["body", "completion"])
    }
}
