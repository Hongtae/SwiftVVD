import XCTest
@testable import VUI

final class TransactionNestingTests: XCTestCase {
    func testKeyPathWithTransactionInstallsScopedValue() {
        var observed = false

        withTransaction(\.disablesAnimations, true) {
            observed = Transaction.current.disablesAnimations
        }

        XCTAssertTrue(observed)
        XCTAssertFalse(Transaction.current.disablesAnimations)
    }

    func testNestedKeyPathWithTransactionMergesParentKeysWithChildPriority() {
        var observedDisablesAnimations = false
        var observedHasAnimation = false

        withTransaction(\.disablesAnimations, true) {
            withTransaction(\.animation, Optional.some(Animation.linear(duration: 0.25))) {
                observedDisablesAnimations = Transaction.current.disablesAnimations
                observedHasAnimation = Transaction.current.animation != nil
            }
        }

        XCTAssertTrue(observedDisablesAnimations)
        XCTAssertTrue(observedHasAnimation)
        XCTAssertFalse(Transaction.current.disablesAnimations)
        XCTAssertNil(Transaction.current.animation)
    }

    func testKeyPathWithTransactionCoversAnimationNilAndGestureProperties() {
        var observedContinuous = false
        var observedTracksVelocity = false
        var observedNestedAnimation: Animation?
        var observedNestedNilDisablesAnimations = false
        var observedFalseClearedDisablesAnimations = true
        var observedFalseClearedContinuous = true
        var observedFalseClearedTracksVelocity = false

        withTransaction(\.isContinuous, true) {
            observedContinuous = Transaction.current.isContinuous
        }
        withTransaction(\.tracksVelocity, true) {
            observedTracksVelocity = Transaction.current.tracksVelocity
        }
        withTransaction(\.disablesAnimations, true) {
            withTransaction(\.animation, Optional.some(Animation.linear(duration: 0.25))) {
                withTransaction(\.animation, Optional<Animation>.none) {
                    observedNestedAnimation = Transaction.current.animation
                    observedNestedNilDisablesAnimations = Transaction.current.disablesAnimations
                }
            }
        }
        withTransaction(\.tracksVelocity, true) {
            withTransaction(\.disablesAnimations, true) {
                withTransaction(\.isContinuous, true) {
                    withTransaction(\.disablesAnimations, false) {
                        withTransaction(\.isContinuous, false) {
                            observedFalseClearedDisablesAnimations = Transaction.current.disablesAnimations
                            observedFalseClearedContinuous = Transaction.current.isContinuous
                            observedFalseClearedTracksVelocity = Transaction.current.tracksVelocity
                        }
                    }
                }
            }
        }

        XCTAssertTrue(observedContinuous)
        XCTAssertTrue(observedTracksVelocity)
        XCTAssertNil(observedNestedAnimation)
        XCTAssertTrue(observedNestedNilDisablesAnimations)
        XCTAssertFalse(observedFalseClearedDisablesAnimations)
        XCTAssertFalse(observedFalseClearedContinuous)
        XCTAssertTrue(observedFalseClearedTracksVelocity)
        XCTAssertFalse(Transaction.current.isContinuous)
        XCTAssertFalse(Transaction.current.tracksVelocity)
    }

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
