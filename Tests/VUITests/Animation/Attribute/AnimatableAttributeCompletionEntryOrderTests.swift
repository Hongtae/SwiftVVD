import XCTest
@testable import VUI

final class AnimatableAttributeCompletionEntryOrderTests: XCTestCase {
    func testRegisteredFiniteEntriesPreserveCriteriaGroupOrder() {
        assertFiniteEntryOrder(
            label: "logicalSame",
            registrations: [
                (.logicallyComplete, "logical1"),
                (.logicallyComplete, "logical2"),
                (.logicallyComplete, "logical3"),
            ],
            expected: [
                "logicalSame logical1",
                "logicalSame logical2",
                "logicalSame logical3",
            ]
        )
        assertFiniteEntryOrder(
            label: "removedSame",
            registrations: [
                (.removed, "removed1"),
                (.removed, "removed2"),
                (.removed, "removed3"),
            ],
            expected: [
                "removedSame removed1",
                "removedSame removed2",
                "removedSame removed3",
            ]
        )
        assertFiniteEntryOrder(
            label: "mixedInterleaved",
            registrations: [
                (.logicallyComplete, "logical1"),
                (.removed, "removed1"),
                (.logicallyComplete, "logical2"),
                (.removed, "removed2"),
                (.logicallyComplete, "logical3"),
                (.removed, "removed3"),
            ],
            expected: [
                "mixedInterleaved removed1",
                "mixedInterleaved removed2",
                "mixedInterleaved removed3",
                "mixedInterleaved logical1",
                "mixedInterleaved logical2",
                "mixedInterleaved logical3",
            ]
        )
        assertFiniteEntryOrder(
            label: "mixedReverseInterleaved",
            registrations: [
                (.removed, "removed1"),
                (.logicallyComplete, "logical1"),
                (.removed, "removed2"),
                (.logicallyComplete, "logical2"),
                (.removed, "removed3"),
                (.logicallyComplete, "logical3"),
            ],
            expected: [
                "mixedReverseInterleaved removed1",
                "mixedReverseInterleaved removed2",
                "mixedReverseInterleaved removed3",
                "mixedReverseInterleaved logical1",
                "mixedReverseInterleaved logical2",
                "mixedReverseInterleaved logical3",
            ]
        )
    }

    func testRegisteredSpringSplitEntriesPreserveInsertionOrderAtEachBoundary() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let animation = Animation.interpolatingSpring(
            mass: 1.0,
            stiffness: 50.0,
            damping: 5.0,
            initialVelocity: 0.0
        )
        var transaction = Transaction(animation: animation)
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("springSplit logical1")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("springSplit logical2")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("springSplit removed1")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("springSplit removed2")
        }

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.setSource(_OpacityEffect(opacity: 1), transaction: transaction)
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        let logicalDuration = animation.box.duration
        let presentationDuration = animation.box.presentationDuration(for: Double(1))
        XCTAssertGreaterThan(presentationDuration, logicalDuration)

        harness.setTime(logicalDuration / 2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        let splitSampleTime = (logicalDuration + presentationDuration) / 2
        harness.setTime(splitSampleTime)
        let logicalValue = harness.currentValue().opacity
        XCTAssertGreaterThan(logicalValue, 0)
        XCTAssertLessThan(logicalValue, 1)
        XCTAssertEqual(recorder.events, [])
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "springSplit logical1",
                "springSplit logical2",
            ]
        )

        var sampleTime = splitSampleTime + animation.box.defaultDisplayFrameInterval
        let finalSampleTime = splitSampleTime + presentationDuration + 1.0
        while sampleTime <= finalSampleTime {
            harness.setTime(sampleTime)
            let value = harness.currentValue().opacity
            if recorder.events.count > 2 {
                XCTAssertEqual(value, 1, accuracy: 0.01)
                break
            }
            harness.flushCompletionActions()
            if recorder.events.count > 2 {
                XCTAssertEqual(value, 1, accuracy: 0.01)
                break
            }
            sampleTime += animation.box.defaultDisplayFrameInterval
        }

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "springSplit logical1",
                "springSplit logical2",
                "springSplit removed1",
                "springSplit removed2",
            ]
        )
    }

    private func assertFiniteEntryOrder(
        label: String,
        registrations: [(AnimationCompletionCriteria, String)],
        expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1.0))
        for (criteria, role) in registrations {
            transaction.addAnimationCompletion(criteria: criteria) {
                recorder.record("\(label) \(role)")
            }
        }

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(_OpacityEffect(opacity: 1), transaction: transaction)
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.50)
        _ = harness.currentValue()
        harness.setTime(0.60)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(2.00)
        XCTAssertEqual(harness.currentValue().opacity, 1.0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(recorder.events, [], file: file, line: line)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, expected, file: file, line: line)
    }
}
