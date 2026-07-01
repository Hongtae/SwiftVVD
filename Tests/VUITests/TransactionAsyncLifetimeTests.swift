import XCTest
@testable import VUI

@MainActor
private final class MainActorWaiter {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

final class TransactionAsyncLifetimeTests: XCTestCase {
    @MainActor
    func testDispatchQueueWorkScheduledInsideScopedTransactionsDoesNotInheritCurrentTransaction() async {
        var events: [String] = []

        let animationWaiter = MainActorWaiter()
        withAnimation(
            .linear(duration: 0.20),
            completionCriteria: .removed
        ) {
            XCTAssertNotNil(Transaction.current.animation)
            events.append("animation body")
            DispatchQueue.main.async {
                events.append(Transaction.current.isEmpty ? "animation dispatch empty" : "animation dispatch inherited")
                animationWaiter.resume()
            }
        } completion: {
            events.append("animation completion")
        }
        events.append("animation returned")
        await animationWaiter.wait()

        let transactionWaiter = MainActorWaiter()
        do {
            var transaction = Transaction(animation: .linear(duration: 0.20))
            transaction.disablesAnimations = true
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("transaction completion")
            }

            withTransaction(transaction) {
                XCTAssertNotNil(Transaction.current.animation)
                XCTAssertTrue(Transaction.current.disablesAnimations)
                events.append("transaction body")
                DispatchQueue.main.async {
                    events.append(Transaction.current.isEmpty ? "transaction dispatch empty" : "transaction dispatch inherited")
                    transactionWaiter.resume()
                }
            }
            events.append("transaction returned")
        }
        await transactionWaiter.wait()

        XCTAssertEqual(
            events,
            [
                "animation body",
                "animation completion",
                "animation returned",
                "animation dispatch empty",
                "transaction body",
                "transaction returned",
                "transaction completion",
                "transaction dispatch empty",
            ]
        )
    }

    @MainActor
    func testMainActorTaskScheduledInsideScopedTransactionsDoesNotInheritCurrentTransaction() async {
        var events: [String] = []

        let animationWaiter = MainActorWaiter()
        withAnimation(
            .linear(duration: 0.20),
            completionCriteria: .removed
        ) {
            XCTAssertNotNil(Transaction.current.animation)
            events.append("animation body")
            Task { @MainActor in
                events.append(Transaction.current.isEmpty ? "animation task empty" : "animation task inherited")
                animationWaiter.resume()
            }
        } completion: {
            events.append("animation completion")
        }
        events.append("animation returned")
        await animationWaiter.wait()

        let transactionWaiter = MainActorWaiter()
        do {
            var transaction = Transaction(animation: .linear(duration: 0.20))
            transaction.disablesAnimations = true
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("transaction completion")
            }

            withTransaction(transaction) {
                XCTAssertNotNil(Transaction.current.animation)
                XCTAssertTrue(Transaction.current.disablesAnimations)
                events.append("transaction body")
                Task { @MainActor in
                    events.append(Transaction.current.isEmpty ? "transaction task empty" : "transaction task inherited")
                    transactionWaiter.resume()
                }
            }
            events.append("transaction returned")
        }
        await transactionWaiter.wait()

        XCTAssertEqual(
            events,
            [
                "animation body",
                "animation completion",
                "animation returned",
                "animation task empty",
                "transaction body",
                "transaction returned",
                "transaction completion",
                "transaction task empty",
            ]
        )
    }

    @MainActor
    func testAsyncWorkScheduledInsideKeyPathTransactionsDoesNotInheritCurrentTransaction() async {
        var events: [String] = []

        withTransaction(\.disablesAnimations, true) {
            XCTAssertTrue(Transaction.current.disablesAnimations)
            events.append("sync body")
        }
        events.append(Transaction.current.isEmpty ? "sync restored" : "sync leaked")

        let dispatchWaiter = MainActorWaiter()
        withTransaction(\.disablesAnimations, true) {
            XCTAssertTrue(Transaction.current.disablesAnimations)
            events.append("dispatch body")
            DispatchQueue.main.async {
                events.append(Transaction.current.isEmpty ? "dispatch empty" : "dispatch inherited")
                dispatchWaiter.resume()
            }
        }
        events.append("dispatch returned")
        await dispatchWaiter.wait()

        let taskWaiter = MainActorWaiter()
        withTransaction(\.animation, Optional.some(Animation.linear(duration: 0.20))) {
            XCTAssertNotNil(Transaction.current.animation)
            events.append("task body")
            Task { @MainActor in
                events.append(Transaction.current.isEmpty ? "task empty" : "task inherited")
                taskWaiter.resume()
            }
        }
        events.append("task returned")
        await taskWaiter.wait()

        let nestedWaiter = MainActorWaiter()
        withTransaction(\.tracksVelocity, true) {
            XCTAssertTrue(Transaction.current.tracksVelocity)
            withTransaction(\.disablesAnimations, true) {
                XCTAssertTrue(Transaction.current.tracksVelocity)
                XCTAssertTrue(Transaction.current.disablesAnimations)
                events.append("nested body")
                Task { @MainActor in
                    events.append(Transaction.current.isEmpty ? "nested task empty" : "nested task inherited")
                    nestedWaiter.resume()
                }
            }
            events.append("nested inner returned")
        }
        events.append("nested outer returned")
        await nestedWaiter.wait()

        XCTAssertEqual(
            events,
            [
                "sync body",
                "sync restored",
                "dispatch body",
                "dispatch returned",
                "dispatch empty",
                "task body",
                "task returned",
                "task empty",
                "nested body",
                "nested inner returned",
                "nested outer returned",
                "nested task empty",
            ]
        )
    }
}
