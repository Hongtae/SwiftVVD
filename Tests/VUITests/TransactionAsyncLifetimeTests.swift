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
}
