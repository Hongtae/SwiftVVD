import XCTest
@testable import VUI

final class AttributeGraphCounterTests: XCTestCase {
    func testGraphCounterStartsAtZeroAndUnknownLanesReturnZero() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            XCTAssertEqual(graph.graphCounter(lane: 1), 0)
            XCTAssertEqual(graph.graphCounter(lane: 0), 0)
            XCTAssertEqual(graph.graphCounter(lane: 2), 0)
            XCTAssertEqual(TransactionID(graph: graph).value, 0)
        }
    }

    func testLazyRuleEvaluationAdvancesCounterOncePerTopLevelUpdate() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let derived = graph.makeRule {
                source.value + 1
            }

            XCTAssertEqual(graph.graphCounter(lane: 1), 0)
            XCTAssertEqual(derived.value, 2)
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)
            XCTAssertEqual(derived.value, 2)
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)

            source.setValue(2)
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)
            XCTAssertEqual(derived.value, 3)
            XCTAssertEqual(graph.graphCounter(lane: 1), 2)
            XCTAssertEqual(TransactionID(graph: graph).value, 2)
        }
    }

    func testNestedRuleEvaluationAdvancesCounterOnlyOnce() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let child = graph.makeRule {
                source.value + 1
            }
            let parent = graph.makeRule {
                child.value + 1
            }

            XCTAssertEqual(parent.value, 3)
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)

            source.setValue(3)
            XCTAssertEqual(parent.value, 5)
            XCTAssertEqual(graph.graphCounter(lane: 1), 2)
        }
    }

    func testSideEffectRuleEvaluationAdvancesCounterPerSynchronousRun() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            var observed: [Int] = []

            graph.makeSideEffectRule {
                observed.append(source.value)
            }

            XCTAssertEqual(observed, [1])
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)

            source.setValue(2)

            XCTAssertEqual(observed, [1, 2])
            XCTAssertEqual(graph.graphCounter(lane: 1), 2)
            XCTAssertEqual(TransactionID(graph: graph).value, 2)
        }
    }

    func testNestedDifferentGraphEvaluationAdvancesEachGraphCounter() {
        let outerGraph = AttributeGraph()
        let outerRef = AttributeGraphRef(graph: outerGraph)
        let innerGraph = AttributeGraph()
        let innerRef = AttributeGraphRef(graph: innerGraph)

        var innerSource: Attribute<Int>!
        var innerDerived: Attribute<Int>!

        innerRef.withCurrent {
            innerSource = innerGraph.makeInput(value: 2)
            innerDerived = innerGraph.makeRule {
                innerSource.value + 10
            }
        }

        outerRef.withCurrent {
            let outerTick = outerGraph.makeInput(value: 0)
            let outerDerived = outerGraph.makeRule {
                _ = outerTick.value
                return innerRef.withCurrent {
                    innerDerived.value
                } + 1
            }

            XCTAssertEqual(outerDerived.value, 13)
            XCTAssertEqual(outerGraph.graphCounter(lane: 1), 1)
            XCTAssertEqual(innerGraph.graphCounter(lane: 1), 1)

            innerRef.withCurrent {
                innerSource.setValue(3)
            }
            XCTAssertEqual(outerGraph.graphCounter(lane: 1), 1)
            XCTAssertEqual(innerGraph.graphCounter(lane: 1), 1)

            outerTick.setValue(1)
            XCTAssertEqual(outerDerived.value, 14)
            XCTAssertEqual(outerGraph.graphCounter(lane: 1), 2)
            XCTAssertEqual(innerGraph.graphCounter(lane: 1), 2)
        }
    }

    func testParentInvalidationMarksKeyPathChildInputsChanged() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)
        let recorder = KeyPathChangedInputRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: KeyPathChangedInputPair(first: 1, second: 10))
            let first = graph.subscriptNode(parent: source, keyPath: \.first)
            let second = graph.subscriptNode(parent: source, keyPath: \.second)
            let output = graph.makeStatefulRule(
                KeyPathChangedInputRule(
                    first: first,
                    second: second,
                    recorder: recorder
                )
            )

            XCTAssertEqual(output.value, 11)

            source.setValue(KeyPathChangedInputPair(first: 2, second: 20))
            XCTAssertEqual(output.value, 22)
        }

        XCTAssertEqual(
            recorder.snapshots,
            [
                KeyPathChangedInputSnapshot(firstChanged: false, secondChanged: false),
                KeyPathChangedInputSnapshot(firstChanged: true, secondChanged: true),
            ]
        )
    }

    func testWithoutTrackingSkipsDependencyAndRestoresRuleContext() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)
        let recorder = TrackingIsolationRecorder()

        ref.withCurrent {
            let tracked = graph.makeInput(value: 1)
            let isolated = graph.makeInput(value: 10)
            let output = graph.makeStatefulRule(
                TrackingIsolationRule(
                    tracked: tracked,
                    isolated: isolated,
                    recorder: recorder
                )
            )

            XCTAssertEqual(output.value, 11)
            XCTAssertEqual(recorder.values, [11])

            isolated.setValue(20)
            XCTAssertEqual(output.value, 11)
            XCTAssertEqual(recorder.values, [11])

            tracked.setValue(2)
            XCTAssertEqual(output.value, 22)
            XCTAssertEqual(recorder.values, [11, 22])
        }
    }
}

private struct KeyPathChangedInputPair: Equatable {
    var first: Int
    var second: Int
}

private struct KeyPathChangedInputSnapshot: Equatable {
    var firstChanged: Bool
    var secondChanged: Bool
}

private final class KeyPathChangedInputRecorder {
    var snapshots: [KeyPathChangedInputSnapshot] = []
}

private struct KeyPathChangedInputRule: StatefulRule {
    typealias Value = Int

    var first: Attribute<Int>
    var second: Attribute<Int>
    var recorder: KeyPathChangedInputRecorder

    mutating func updateValue() {
        recorder.snapshots.append(
            KeyPathChangedInputSnapshot(
                firstChanged: AttributeGraph.currentStatefulInputChanged(first.identifier),
                secondChanged: AttributeGraph.currentStatefulInputChanged(second.identifier)
            )
        )
        AttributeGraph.setStatefulOutput(first.value + second.value)
    }
}

private final class TrackingIsolationRecorder {
    var values: [Int] = []
}

private struct TrackingIsolationRule: StatefulRule {
    typealias Value = Int

    var tracked: Attribute<Int>
    var isolated: Attribute<Int>
    var recorder: TrackingIsolationRecorder

    mutating func updateValue() {
        let value = tracked.value + AttributeGraph.withoutTracking {
            isolated.value
        }
        recorder.values.append(value)
        AttributeGraph.setStatefulOutput(value)
    }
}
