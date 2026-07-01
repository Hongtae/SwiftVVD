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
    let value: Int

    init(_ value: Int) {
        self.value = value
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
    }

    func testAGBackedSameValueWriteUsesNoMutationCompletionTiming() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0.4)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0.4, accuracy: 0.000001)

        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("same completion")
        }

        withTransaction(transaction) {
            events.append("same body")
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 0.4))
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
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0.4)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0.4, accuracy: 0.000001)

        var events: [String] = []
        withAnimation(
            .linear(duration: 0.20),
            completionCriteria: .removed
        ) {
            events.append("same animation body")
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 0.4))
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

    func testAGBackedSemanticEqualDifferentStorageWriteUsesMutationFallbackTiming() {
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

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(
            events,
            [
                "semantic ag body",
                "semantic ag returned",
            ]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertEqual(
            events,
            [
                "semantic ag body",
                "semantic ag returned",
                "semantic ag completion",
            ]
        )
    }

    func testAGInputArrayEqualContentsWriteUsesStorageComparisonFallbackTiming() {
        let host = GraphHost()
        var input: Attribute<[Int]>!
        host.data.withCurrent {
            input = host.data.graph.makeInput(value: [1, 2, 3])
        }

        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("array completion")
        }

        withTransaction(transaction) {
            events.append("array body")
            let nextValue = [1, 2, 3].map { $0 }
            host.data.withCurrent {
                input.setValue(nextValue, transaction: Transaction.current)
            }
        }
        events.append("array returned")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(
            events,
            [
                "array body",
                "array returned",
            ]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertEqual(
            events,
            [
                "array body",
                "array returned",
                "array completion",
            ]
        )
    }

    func testStoredLocationRawEqualWriteUsesNoMutationCompletionTiming() {
        let location = StoredLocationBase<NonHashableEquatablePayload>(
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

    func testStoredLocationSemanticEqualDifferentStorageUsesMutationFallbackTiming() {
        let location = StoredLocationBase<SemanticEquatablePayload>(
            initialValue: SemanticEquatablePayload(value: 1, ignored: 10)
        )

        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("semantic completion")
        }

        withTransaction(transaction) {
            events.append("semantic body")
            location.setValue(
                SemanticEquatablePayload(value: 1, ignored: 11),
                transaction: Transaction.current
            )
        }
        events.append("semantic returned")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(
            events,
            [
                "semantic body",
                "semantic returned",
            ]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertEqual(
            events,
            [
                "semantic body",
                "semantic returned",
                "semantic completion",
            ]
        )
    }

    func testAGBackedChangedWriteUsesWriteNoTokenFallbackTiming() {
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

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(
            events,
            [
                "changed body",
                "changed returned",
            ]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
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
