import XCTest
@testable import VUI

final class AGUpdateCancellationTests: XCTestCase {
    func testOrdinaryStatefulUpdateIsNotCancelled() {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        let recorder = AGCancellationRecorder()

        context.withCurrent {
            let source = graph.makeInput(value: 7)
            let output = graph.makeStatefulRule(
                AGCancelingRule(source: source, recorder: recorder)
            )

            XCTAssertEqual(output.value, 7)
        }

        XCTAssertEqual(recorder.beforeCancellation, [false])
        XCTAssertEqual(recorder.afterCancellation, [false])
        XCTAssertEqual(recorder.cancelIfNeeded, [false])
    }

    func testCancellationStateIsVisibleOnlyDuringTheCurrentUpdate() {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        let recorder = AGCancellationRecorder()

        context.withCurrent {
            let source = graph.makeInput(value: 1)
            let output = graph.makeStatefulRule(
                AGCancelingRule(source: source, recorder: recorder)
            )

            recorder.shouldCancel = true
            XCTAssertEqual(output.value, 1)

            source.setValue(2)
            XCTAssertEqual(output.value, 2)
        }

        XCTAssertEqual(recorder.beforeCancellation, [false, false])
        XCTAssertEqual(recorder.afterCancellation, [true, false])
        XCTAssertEqual(recorder.cancelIfNeeded, [true, false])
    }

    func testCancelledStatefulOutputRemainsDirtyForRetry() {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        let recorder = AGCancellationRecorder()

        context.withCurrent {
            let source = graph.makeInput(value: 5)
            let output = graph.makeStatefulRule(
                AGCancelingRule(source: source, recorder: recorder)
            )

            recorder.shouldCancel = true
            XCTAssertEqual(output.value, 5)
            XCTAssertEqual(recorder.afterCancellation, [true])

            XCTAssertEqual(output.value, 5)
            XCTAssertEqual(recorder.afterCancellation, [true, false])

            XCTAssertEqual(output.value, 5)
            XCTAssertEqual(recorder.afterCancellation, [true, false])
        }

        XCTAssertEqual(recorder.beforeCancellation, [false, false])
        XCTAssertEqual(recorder.cancelIfNeeded, [true, false])
        XCTAssertEqual(recorder.inputsChanged, [true, true])
    }

    func testCancelledRetryReusesItsDynamicInputEdge() {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        let recorder = AGCancellationRecorder()

        context.withCurrent {
            let source = graph.makeInput(value: 5)
            let output = graph.makeStatefulRule(
                AGCancelingRule(source: source, recorder: recorder)
            )
            let outputIndex = Int(output.identifier.rawValue)
            let sourceIndex = Int(source.identifier.rawValue)

            recorder.shouldCancel = true
            XCTAssertEqual(output.value, 5)
            XCTAssertEqual(
                graph.slots[outputIndex].node!.pointee.inputs.filter {
                    $0.attribute == source.identifier.rawValue
                }.count,
                1
            )

            XCTAssertEqual(output.value, 5)
            XCTAssertEqual(
                graph.slots[outputIndex].node!.pointee.inputs.filter {
                    $0.attribute == source.identifier.rawValue
                }.count,
                1
            )
            XCTAssertEqual(
                graph.slots[sourceIndex].node!.pointee.outputs.filter {
                    $0 == output.identifier.rawValue
                }.count,
                1
            )
            XCTAssertEqual(
                graph.slots[outputIndex].node!.pointee.inputs[0].flags
                    & _AGGraph.InputEdge.readThisEvaluation,
                0
            )
        }
    }

    func testEstablishedChildCancellationDefersParentPublicationUntilRetry() {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        let recorder = AGCancellationRecorder()

        context.withCurrent {
            let source = graph.makeInput(value: 1)
            let child = graph.makeStatefulRule(
                AGCancelingRule(source: source, recorder: recorder)
            )
            let parent = graph.makeRule {
                recorder.parentEvaluationCount += 1
                return child.value * 10
            }

            XCTAssertEqual(parent.value, 10)
            XCTAssertEqual(recorder.parentEvaluationCount, 1)

            recorder.shouldCancel = true
            source.setValue(2)

            XCTAssertEqual(parent.value, 10)
            XCTAssertEqual(recorder.parentEvaluationCount, 1)
            XCTAssertEqual(child.value, 2)

            XCTAssertEqual(parent.value, 20)
            XCTAssertEqual(recorder.parentEvaluationCount, 2)
        }

        XCTAssertEqual(recorder.afterCancellation, [false, true, false])
    }

    func testNestedChildCancellationPropagatesToTheOuterUpdateContext() {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        let recorder = AGCancellationRecorder()

        context.withCurrent {
            let source = graph.makeInput(value: 3)
            let child = graph.makeStatefulRule(
                AGCancelingRule(source: source, recorder: recorder)
            )
            let parent = graph.makeStatefulRule(
                AGNestedCancellationParentRule(
                    child: child,
                    recorder: recorder
                )
            )

            recorder.shouldCancel = true
            XCTAssertEqual(parent.value, 30)
            XCTAssertEqual(parent.value, 30)
            XCTAssertEqual(parent.value, 30)
        }

        XCTAssertEqual(recorder.outerCancellation, [true, false])
    }
}

private final class AGCancellationRecorder {
    var shouldCancel = false
    var beforeCancellation: [Bool] = []
    var afterCancellation: [Bool] = []
    var cancelIfNeeded: [Bool] = []
    var inputsChanged: [Bool] = []
    var outerCancellation: [Bool] = []
    var parentEvaluationCount = 0
}

private struct AGCancelingRule: StatefulRule {
    typealias Value = Int

    var source: Attribute<Int>
    var recorder: AGCancellationRecorder

    mutating func updateValue() {
        let newValue = source.value
        recorder.inputsChanged.append(_AGGraphAnyInputsChanged())
        recorder.beforeCancellation.append(updateWasCancelled)
        if recorder.shouldCancel {
            recorder.shouldCancel = false
            _AGGraphCancelUpdate()
        }
        recorder.afterCancellation.append(updateWasCancelled)
        recorder.cancelIfNeeded.append(_AGGraphCancelUpdateIfNeeded())
        value = newValue
    }
}

private struct AGNestedCancellationParentRule: StatefulRule {
    typealias Value = Int

    var child: Attribute<Int>
    var recorder: AGCancellationRecorder

    mutating func updateValue() {
        let childValue = child.value
        recorder.outerCancellation.append(updateWasCancelled)
        value = childValue * 10
    }
}
