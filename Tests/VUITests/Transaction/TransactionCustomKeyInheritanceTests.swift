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

    func testScopedTransactionDoesNotInheritParentCompletionListener() throws {
        var parent = Transaction(animation: .linear(duration: 1))
        parent.addAnimationCompletion {}

        let scoped = Transaction().scopedTransaction(inheritingFrom: parent)

        XCTAssertNotNil(scoped.animation)
        XCTAssertNil(scoped.animationListener)
        XCTAssertNil(scoped.animationLogicalListener)
    }

    func testNestedWithTransactionCurrentDoesNotInheritParentCompletionListener() {
        var parent = Transaction(animation: .linear(duration: 1))
        parent.addAnimationCompletion {}
        var observedAnimation: Animation?
        var observedListener: AnimationListener?
        var observedLogicalListener: AnimationListener?

        withTransaction(parent) {
            withTransaction(Transaction()) {
                let current = Transaction.current
                observedAnimation = current.animation
                observedListener = current.animationListener
                observedLogicalListener = current.animationLogicalListener
            }
        }

        XCTAssertNotNil(observedAnimation)
        XCTAssertNil(observedListener)
        XCTAssertNil(observedLogicalListener)
    }

    func testScopedTransactionKeepsInnerCompletionListener() throws {
        var parent = Transaction(animation: .linear(duration: 1))
        parent.addAnimationCompletion {}
        var child = Transaction()
        child.addAnimationCompletion {}

        let scoped = child.scopedTransaction(inheritingFrom: parent)

        XCTAssertNotNil(scoped.animation)
        XCTAssertTrue(
            try XCTUnwrap(scoped.animationLogicalListener) ===
                XCTUnwrap(child.animationLogicalListener)
        )
        XCTAssertFalse(
            try XCTUnwrap(scoped.animationLogicalListener) ===
                XCTUnwrap(parent.animationLogicalListener)
        )
    }
}
