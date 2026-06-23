import XCTest
@testable import VUI

final class TransactionNestingTests: XCTestCase {
    func testNestedEmptyTransactionInheritsParentKeys() {
        var parent = Transaction(animation: .linear(duration: 1))
        parent.disablesAnimations = true
        parent.isContinuous = true
        parent.tracksVelocity = true

        let scoped = Transaction().scopedTransaction(inheritingFrom: parent)

        XCTAssertNotNil(scoped.animation)
        XCTAssertTrue(scoped.disablesAnimations)
        XCTAssertTrue(scoped.isContinuous)
        XCTAssertTrue(scoped.tracksVelocity)
    }

    func testNestedExplicitNilAndFalseKeysClearParentKeys() {
        var parent = Transaction(animation: .linear(duration: 1))
        parent.disablesAnimations = true
        parent.isContinuous = true
        parent.tracksVelocity = true

        var child = Transaction(animation: nil)
        child.disablesAnimations = false
        child.isContinuous = false
        child.tracksVelocity = false

        let scoped = child.scopedTransaction(inheritingFrom: parent)

        XCTAssertNil(scoped.animation)
        XCTAssertFalse(scoped.disablesAnimations)
        XCTAssertFalse(scoped.isContinuous)
        XCTAssertFalse(scoped.tracksVelocity)
    }

    func testNestedTransactionKeepsSeparateCompletionObserver() throws {
        var outer = Transaction(animation: .linear(duration: 1))
        outer.addAnimationCompletion {}

        var inner = Transaction()
        inner.addAnimationCompletion {}

        try withTransaction(outer) {
            try withTransaction(inner) {
                let current = Transaction.current
                XCTAssertNotNil(current.animation)
                XCTAssertTrue(
                    try XCTUnwrap(current.animationCompletionObserver) ===
                        XCTUnwrap(inner.animationCompletionObserver)
                )
                XCTAssertFalse(
                    try XCTUnwrap(current.animationCompletionObserver) ===
                        XCTUnwrap(outer.animationCompletionObserver)
                )
            }
        }
    }
}
