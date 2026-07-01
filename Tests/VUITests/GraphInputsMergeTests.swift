import XCTest
@testable import VUI

final class GraphInputsMergeTests: XCTestCase {
    func testMergePreservesReceiverOptionsAndImportsOnlyOtherAnimationsDisabled() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var receiver = makeGraphInputs(graph: graph)
            receiver.options = [
                .supportsVariableFrameDuration,
                .viewNeedsGeometry,
            ]

            var other = makeGraphInputs(graph: graph)
            other.options = [
                .animationsDisabled,
                .viewRequestsLayoutComputer,
                .viewNeedsGeometryAccessibility,
                .needsAccessibility,
                .needsDynamicLayout,
            ]

            receiver.merge(other, ignoringPhase: false)

            XCTAssertTrue(receiver.options.contains(.supportsVariableFrameDuration))
            XCTAssertTrue(receiver.options.contains(.viewNeedsGeometry))
            XCTAssertTrue(receiver.options.contains(.animationsDisabled))
            XCTAssertFalse(receiver.options.contains(.viewRequestsLayoutComputer))
            XCTAssertFalse(receiver.options.contains(.viewNeedsGeometryAccessibility))
            XCTAssertFalse(receiver.options.contains(.needsAccessibility))
            XCTAssertFalse(receiver.options.contains(.needsDynamicLayout))
        }
    }

    func testMergeDoesNotImportOtherSupportsVariableFrameDuration() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var receiver = makeGraphInputs(graph: graph)
            var other = makeGraphInputs(graph: graph)
            other.options = [.supportsVariableFrameDuration]

            receiver.merge(other)

            XCTAssertFalse(receiver.options.contains(.supportsVariableFrameDuration))
        }
    }

    private func makeGraphInputs(graph: _AGGraph) -> _GraphInputs {
        _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time()),
            cachedEnvironment: MutableBox(
                CachedEnvironment(
                    environment: graph.makeInput(value: EnvironmentValues.tracking())
                )
            ),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
    }
}
