import XCTest
@testable import VUI

private struct CustomScopedTransactionKey: TransactionKey {
    static let defaultValue = 0
}

final class TransactionCustomKeyInheritanceTests: XCTestCase {
    func testNestedEmptyTransactionInheritsCustomTransactionKey() {
        var parent = Transaction()
        parent[CustomScopedTransactionKey.self] = 7

        let scoped = Transaction().scopedTransaction(inheritingFrom: parent)

        XCTAssertEqual(scoped[CustomScopedTransactionKey.self], 7)
    }

    func testNestedExplicitCustomTransactionKeyOverridesParent() {
        var parent = Transaction()
        parent[CustomScopedTransactionKey.self] = 7
        var child = Transaction()
        child[CustomScopedTransactionKey.self] = 3

        let scoped = child.scopedTransaction(inheritingFrom: parent)

        XCTAssertEqual(scoped[CustomScopedTransactionKey.self], 3)
    }

    func testNestedWithTransactionCurrentInheritsCustomTransactionKey() {
        var parent = Transaction()
        parent[CustomScopedTransactionKey.self] = 7
        var observed = 0

        withTransaction(parent) {
            withTransaction(Transaction()) {
                observed = Transaction.current[CustomScopedTransactionKey.self]
            }
        }

        XCTAssertEqual(observed, 7)
    }

    func testScopedTransactionDoesNotInheritParentCompletionObserver() throws {
        var parent = Transaction(animation: .linear(duration: 1))
        parent.addAnimationCompletion {}

        let scoped = Transaction().scopedTransaction(inheritingFrom: parent)

        XCTAssertNotNil(scoped.animation)
        XCTAssertNil(scoped.animationCompletionObserver)
        XCTAssertNil(scoped.animationListener)
        XCTAssertNil(scoped.animationLogicalListener)
    }

    func testNestedWithTransactionCurrentDoesNotInheritParentCompletionObserver() {
        var parent = Transaction(animation: .linear(duration: 1))
        parent.addAnimationCompletion {}
        var observedAnimation: Animation?
        var observedObserver: AnimationCompletionObserver?
        var observedListener: AnimationListener?
        var observedLogicalListener: AnimationListener?

        withTransaction(parent) {
            withTransaction(Transaction()) {
                let current = Transaction.current
                observedAnimation = current.animation
                observedObserver = current.animationCompletionObserver
                observedListener = current.animationListener
                observedLogicalListener = current.animationLogicalListener
            }
        }

        XCTAssertNotNil(observedAnimation)
        XCTAssertNil(observedObserver)
        XCTAssertNil(observedListener)
        XCTAssertNil(observedLogicalListener)
    }

    func testScopedTransactionKeepsInnerCompletionObserver() throws {
        var parent = Transaction(animation: .linear(duration: 1))
        parent.addAnimationCompletion {}
        var child = Transaction()
        child.addAnimationCompletion {}

        let scoped = child.scopedTransaction(inheritingFrom: parent)

        XCTAssertNotNil(scoped.animation)
        XCTAssertTrue(
            try XCTUnwrap(scoped.animationCompletionObserver) ===
                XCTUnwrap(child.animationCompletionObserver)
        )
        XCTAssertFalse(
            try XCTUnwrap(scoped.animationCompletionObserver) ===
                XCTUnwrap(parent.animationCompletionObserver)
        )
    }
}
