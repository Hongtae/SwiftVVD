import XCTest
@testable import VUI

final class AGInputScanTests: XCTestCase {
    func testExcludedUpdatePreservesCachedChildDependency() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let trigger = graph.makeInput(value: 0)
            let child = graph.makeInput(value: 10)
            let recorder = InputScanRecorder()
            let output = graph.makeStatefulRule(CachedInputScan(
                trigger: trigger, child: child, recorder: recorder
            ))

            XCTAssertEqual(output.value, 10)
            trigger.setValue(1)
            XCTAssertEqual(output.value, 10)
            trigger.setValue(2)
            XCTAssertEqual(output.value, 10)
            XCTAssertEqual(recorder.changed, [false, false])
            XCTAssertEqual(recorder.childReads, 1)

            child.setValue(20)
            XCTAssertEqual(output.value, 20)
            XCTAssertEqual(recorder.changed, [false, false, true])
            XCTAssertEqual(recorder.childReads, 2)
        }
    }

    func testQualifyingChangeStopsBeforeUnvisitedDependencies() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let first = graph.makeInput(value: 1)
            let later = graph.makeInput(value: 2)
            let recorder = InputScanRecorder()
            let output = graph.makeStatefulRule(EarlyInputScan(
                first: first, later: later, recorder: recorder
            ))

            XCTAssertEqual(output.value, 1)
            first.setValue(3)
            XCTAssertEqual(output.value, 2)
            XCTAssertEqual(recorder.changed, [true])

            // The scan stopped at the first changed edge and the rule did not
            // read the later input, so that dependency is no longer retained.
            later.setValue(4)
            XCTAssertEqual(output.value, 2)
            XCTAssertEqual(recorder.changed, [true])
        }
    }

    func testEmptyInputScanDoesNotReportNodeInvalidationAsAnInputChange() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let output = graph.makeRule { _AGGraphAnyInputsChanged() }
            XCTAssertFalse(output.value)
            graph.invalidateAttribute(output.identifier)
            XCTAssertFalse(output.value)
        }
    }
}

private final class InputScanRecorder {
    var changed: [Bool] = []
    var childReads = 0
}

private struct CachedInputScan: StatefulRule {
    typealias Value = Int
    let trigger: Attribute<Int>
    let child: Attribute<Int>
    let recorder: InputScanRecorder

    mutating func updateValue() {
        _ = trigger.value
        var needsRead = !hasValue
        if hasValue {
            var excluded = trigger.identifier.rawValue
            let changed = withUnsafePointer(to: &excluded) {
                _AGGraphAnyInputsChanged($0, 1)
            }
            recorder.changed.append(changed)
            needsRead = changed
        }
        if needsRead {
            recorder.childReads += 1
            value = child.value
        }
    }
}

private struct EarlyInputScan: StatefulRule {
    typealias Value = Int
    let first: Attribute<Int>
    let later: Attribute<Int>
    let recorder: InputScanRecorder

    mutating func updateValue() {
        if !hasValue {
            _ = first.value
            _ = later.value
            value = 1
        } else {
            recorder.changed.append(_AGGraphAnyInputsChanged())
            value += 1
        }
    }
}
