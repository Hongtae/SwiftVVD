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
