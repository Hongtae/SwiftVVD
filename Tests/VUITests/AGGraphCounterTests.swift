import Synchronization
import XCTest
@testable import VUI

final class AGGraphCounterTests: XCTestCase {
    func testGraphCounterStartsAtZeroAndUnknownLanesReturnZero() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            XCTAssertEqual(graph.graphCounter(lane: 1), 0)
            XCTAssertEqual(graph.graphCounter(lane: 0), 0)
            XCTAssertEqual(graph.graphCounter(lane: 2), 0)
            XCTAssertEqual(TransactionID(graph: graph).value, 0)
        }
    }

    func testLazyRuleEvaluationAdvancesCounterOncePerTopLevelUpdate() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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

    func testEagerSideEffectDoesNotReenterWhileDependencyMutatesDuringEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 0)
            let derived = graph.makeRule {
                let value = source.value
                if value == 0 {
                    source.setValue(1)
                }
                return source.value + 10
            }
            var observed: [Int] = []

            graph.makeSideEffectRule {
                observed.append(derived.value)
            }

            XCTAssertEqual(observed, [11])
            XCTAssertEqual(derived.value, 11)
        }
    }

    func testRemovingKeyPathInputDetachesSideEffectFromRemainingParentDependencies() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(
                value: KeyPathChangedInputPair(first: 1, second: 10)
            )
            let first = graph.subscriptNode(parent: source, keyPath: \.first)
            let trigger = graph.makeInput(value: 100)
            var observed: [Int] = []

            graph.makeSideEffectRule {
                observed.append(first.value + trigger.value)
            }
            XCTAssertEqual(observed, [101])

            graph.removeNode(first.identifier)
            trigger.setValue(200)
            source.setValue(KeyPathChangedInputPair(first: 2, second: 20))

            XCTAssertEqual(observed, [101])
        }
    }

    func testNestedDifferentGraphEvaluationAdvancesEachGraphCounter() {
        let outerGraph = _AGGraph()
        let outerRef = _AGGraphContext(graph: outerGraph)
        let innerGraph = _AGGraph()
        let innerRef = _AGGraphContext(graph: innerGraph)

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

    func testCurrentContextDoesNotPropagateToChildTask() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let probe = CurrentContextTaskProbe(graph: graph)

        ref.withCurrent {
            Task {
                probe.run()
            }
            XCTAssertEqual(probe.wait(), .success)
        }

        XCTAssertFalse(probe.observed)
    }

    func testCurrentContextTokenMapAllowsReturningToOuterGraph() {
        let outerGraph = _AGGraph()
        let outerRef = _AGGraphContext(graph: outerGraph)
        let innerGraph = _AGGraph()
        let innerRef = _AGGraphContext(graph: innerGraph)

        outerRef.withCurrent {
            XCTAssertTrue(_AGGraph.current === outerGraph)

            innerRef.withCurrent {
                XCTAssertTrue(_AGGraph.current === innerGraph)

                outerRef.withCurrent {
                    XCTAssertTrue(_AGGraph.current === outerGraph)
                }

                XCTAssertTrue(_AGGraph.current === innerGraph)
            }

            XCTAssertTrue(_AGGraph.current === outerGraph)
        }
    }

    func testParentInvalidationMarksKeyPathChildInputsChanged() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
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
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
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
                firstChanged: _AGGraph.currentStatefulInputChanged(first.identifier),
                secondChanged: _AGGraph.currentStatefulInputChanged(second.identifier)
            )
        )
        _AGGraph.setStatefulOutput(first.value + second.value)
    }
}

private final class TrackingIsolationRecorder {
    var values: [Int] = []
}

private final class CurrentContextTaskProbe: @unchecked Sendable {
    let graph: _AGGraph
    private let semaphore = DispatchSemaphore(value: 0)
    private let observedCurrent = Mutex(false)

    init(graph: _AGGraph) {
        self.graph = graph
    }

    func run() {
        observedCurrent.withLock { value in
            value = _AGGraph.current === graph
        }
        semaphore.signal()
    }

    func wait() -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + 2)
    }

    var observed: Bool {
        observedCurrent.withLock { $0 }
    }
}

private struct TrackingIsolationRule: StatefulRule {
    typealias Value = Int

    var tracked: Attribute<Int>
    var isolated: Attribute<Int>
    var recorder: TrackingIsolationRecorder

    mutating func updateValue() {
        let value = tracked.value + _AGGraph.withoutTracking {
            isolated.value
        }
        recorder.values.append(value)
        _AGGraph.setStatefulOutput(value)
    }
}
