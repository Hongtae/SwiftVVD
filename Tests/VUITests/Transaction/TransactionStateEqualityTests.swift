import XCTest
@testable import VUI

private struct NonHashableEquatablePayload: Equatable {
    var value: Int
}

private struct SemanticEquatablePayload: Equatable {
    var value: Int
    var ignored: Int

    static func == (lhs: SemanticEquatablePayload, rhs: SemanticEquatablePayload) -> Bool {
        lhs.value == rhs.value
    }
}

private struct SemanticAnimatablePayload: Animatable, Equatable {
    var value: Double
    var ignored: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(value, ignored) }
        set {
            value = newValue.first
            ignored = newValue.second
        }
    }

    static func == (lhs: SemanticAnimatablePayload, rhs: SemanticAnimatablePayload) -> Bool {
        lhs.value == rhs.value
    }
}

private struct PlainPayload {
    var value: Int
}

private final class ReferencePayload {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }
}

private final class SemanticEquatableReference: Equatable {
    nonisolated(unsafe) static var equalityCallCount = 0

    var value: Int

    init(_ value: Int) {
        self.value = value
    }

    static func == (lhs: SemanticEquatableReference, rhs: SemanticEquatableReference) -> Bool {
        equalityCallCount += 1
        return lhs.value == rhs.value
    }
}

final class TransactionStateEqualityTests: XCTestCase {
    func testStateKnownEqualUsesHashableOrRawRepresentationOnly() {
        XCTAssertTrue(_stateValuesAreKnownEqual(AnyHashable(1), AnyHashable(1)))
        XCTAssertFalse(_stateValuesAreKnownEqual(AnyHashable(1), AnyHashable(2)))

        XCTAssertTrue(
            _stateValuesAreKnownEqual(
                NonHashableEquatablePayload(value: 1),
                NonHashableEquatablePayload(value: 1)
            )
        )
        XCTAssertFalse(
            _stateValuesAreKnownEqual(
                SemanticEquatablePayload(value: 1, ignored: 10),
                SemanticEquatablePayload(value: 1, ignored: 11)
            )
        )

        let plain = PlainPayload(value: 1)
        XCTAssertTrue(_stateValuesAreKnownEqual(plain, plain))

        let reference = ReferencePayload(1)
        XCTAssertTrue(_stateValuesAreKnownEqual(reference, reference))
        XCTAssertFalse(_stateValuesAreKnownEqual(reference, ReferencePayload(1)))
    }

    func testAGGraphCompareValuesUsesStringAndStorageComparison() {
        let options = AGComparisonOptions(rawValue: 3)

        XCTAssertTrue(_AGGraph.compareValues(7, 7, options: options))
        XCTAssertFalse(_AGGraph.compareValues(7, 8, options: options))

        XCTAssertTrue(
            _AGGraph.compareValues(
                String(repeating: "a", count: 32),
                String(repeating: "a", count: 32),
                options: options
            )
        )
        XCTAssertFalse(
            _AGGraph.compareValues(
                [1, 2, 3],
                [1, 2, 3].map { $0 },
                options: options
            )
        )
        XCTAssertFalse(
            _AGGraph.compareValues(
                SemanticEquatablePayload(value: 1, ignored: 10),
                SemanticEquatablePayload(value: 1, ignored: 11),
                options: options
            )
        )

        let reference = ReferencePayload(1)
        let referenceAlias = reference
        XCTAssertTrue(_AGGraph.compareValues(reference, referenceAlias, options: options))
        reference.value = 2
        XCTAssertTrue(_AGGraph.compareValues(reference, referenceAlias, options: options))
        XCTAssertFalse(_AGGraph.compareValues(reference, ReferencePayload(2), options: options))

        SemanticEquatableReference.equalityCallCount = 0
        XCTAssertFalse(
            _AGGraph.compareValues(
                SemanticEquatableReference(1),
                SemanticEquatableReference(1),
                options: options
            )
        )
        XCTAssertEqual(SemanticEquatableReference.equalityCallCount, 0)
    }

    func testAGBackedSameValueWriteUsesNoMutationCompletionTiming() {
        let host = GraphHost()
        var input: Attribute<_OpacityEffect>!
        host.data.withCurrent {
            input = host.data.graph.makeInput(
                value: _OpacityEffect(opacity: 0.4)
            )
        }

        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("same completion")
        }

        withTransaction(transaction) {
            events.append("same body")
            host.data.withCurrent {
                XCTAssertFalse(
                    input.setValue(
                        _OpacityEffect(opacity: 0.4),
                        transaction: Transaction.current
                    )
                )
            }
        }
        events.append("same returned")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(
            events,
            [
                "same body",
                "same returned",
                "same completion",
            ]
        )
    }

    func testAGBackedSameValueWriteWithAnimationCompletesBeforeReturn() {
        let host = GraphHost()
        var input: Attribute<_OpacityEffect>!
        host.data.withCurrent {
            input = host.data.graph.makeInput(
                value: _OpacityEffect(opacity: 0.4)
            )
        }

        var events: [String] = []
        withAnimation(
            .linear(duration: 0.20),
            completionCriteria: .removed
        ) {
            events.append("same animation body")
            host.data.withCurrent {
                XCTAssertFalse(
                    input.setValue(
                        _OpacityEffect(opacity: 0.4),
                        transaction: Transaction.current
                    )
                )
            }
        } completion: {
            events.append("same animation completion")
        }
        events.append("same animation returned")

        XCTAssertEqual(
            events,
            [
                "same animation body",
                "same animation completion",
                "same animation returned",
            ]
        )
    }

    func testAGBackedSemanticEqualDifferentStorageWriteRegistersAnimatorListener() {
        let harness = GenericAnimatableAttributeHarness<SemanticAnimatablePayload>(
            initialValue: SemanticAnimatablePayload(value: 1, ignored: 10)
        )
        XCTAssertEqual(harness.currentValue().value, 1, accuracy: 0.000001)
        XCTAssertEqual(harness.currentValue().ignored, 10, accuracy: 0.000001)

        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("semantic ag completion")
        }

        withTransaction(transaction) {
            events.append("semantic ag body")
            harness.setSource(
                SemanticAnimatablePayload(value: 1, ignored: 11),
                transaction: Transaction.current
            )
        }
        events.append("semantic ag returned")

        XCTAssertTrue(harness.valueNeedsEvaluation())
        _ = harness.currentValue()
        XCTAssertEqual(
            events,
            [
                "semantic ag body",
                "semantic ag returned",
            ]
        )

        harness.advanceTime(to: 0.25)
        _ = harness.currentValue()
        XCTAssertEqual(
            events,
            [
                "semantic ag body",
                "semantic ag returned",
                "semantic ag completion",
            ]
        )
    }

    func testAGInputArrayEqualContentsWriteUsesStorageComparison() {
        let host = GraphHost()
        var input: Attribute<[Int]>!
        host.data.withCurrent {
            input = host.data.graph.makeInput(value: [1, 2, 3])
        }

        let nextValue = [1, 2, 3].map { $0 }
        host.data.withCurrent {
            XCTAssertTrue(
                input.setValue(
                    nextValue,
                    transaction: Transaction(animation: .linear(duration: 0.20))
                )
            )
            XCTAssertEqual(input.value, [1, 2, 3])
        }
    }

    func testStoredLocationRawEqualWriteUsesNoMutationCompletionTiming() {
        let location = TestStoredLocation<NonHashableEquatablePayload>(
            initialValue: NonHashableEquatablePayload(value: 1)
        )

        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("raw-equal completion")
        }

        withTransaction(transaction) {
            events.append("raw-equal body")
            location.setValue(
                NonHashableEquatablePayload(value: 1),
                transaction: Transaction.current
            )
        }
        events.append("raw-equal returned")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(
            events,
            [
                "raw-equal body",
                "raw-equal returned",
                "raw-equal completion",
            ]
        )
    }

    func testStoredLocationSemanticEqualDifferentStorageCommitsMutation() {
        let location = TestStoredLocation<SemanticEquatablePayload>(
            initialValue: SemanticEquatablePayload(value: 1, ignored: 10)
        )
        var committed: [SemanticEquatablePayload] = []
        var committedWithAnimation = false
        location.setCommitValueHandler { value, transaction in
            committed.append(value)
            committedWithAnimation = transaction.animation != nil
        }

        let transaction = Transaction(animation: .linear(duration: 0.20))

        withTransaction(transaction) {
            location.setValue(
                SemanticEquatablePayload(value: 1, ignored: 11),
                transaction: Transaction.current
            )
        }

        XCTAssertEqual(
            committed,
            [SemanticEquatablePayload(value: 1, ignored: 11)]
        )
        XCTAssertTrue(committedWithAnimation)
    }

    func testAGBackedChangedWriteRegistersAnimatorListener() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0.4)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0.4, accuracy: 0.000001)

        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("changed completion")
        }

        withTransaction(transaction) {
            events.append("changed body")
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 0.8))
        }
        events.append("changed returned")

        XCTAssertTrue(harness.valueNeedsEvaluation())
        _ = harness.currentValue()
        XCTAssertEqual(
            events,
            [
                "changed body",
                "changed returned",
            ]
        )

        harness.advanceTime(to: 0.25)
        _ = harness.currentValue()
        XCTAssertEqual(
            events,
            [
                "changed body",
                "changed returned",
                "changed completion",
            ]
        )
    }
}
