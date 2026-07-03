import XCTest
@testable import VUI

final class GraphInputsMergeTests: XCTestCase {
    func testUsingGraphicsRendererIsBoolViewInputWithSeparateViewChannel() {
        assertBoolViewInput(UsingGraphicsRenderer.self)

        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)

            XCTAssertFalse(inputs[UsingGraphicsRenderer.self])
            XCTAssertFalse(inputs.base[UsingGraphicsRenderer.self])

            inputs[UsingGraphicsRenderer.self] = true

            XCTAssertTrue(inputs[UsingGraphicsRenderer.self])
            XCTAssertFalse(inputs.base[UsingGraphicsRenderer.self])

            inputs.base[UsingGraphicsRenderer.self] = true

            XCTAssertTrue(inputs[UsingGraphicsRenderer.self])
            XCTAssertTrue(inputs.base[UsingGraphicsRenderer.self])
        }
    }

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

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        _ViewInputs(
            base: makeGraphInputs(graph: graph),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(CGSize(width: 10, height: 10))),
            safeAreaInsets: OptionalAttribute<SafeAreaInsets>(),
            containerSize: OptionalAttribute<ViewSize>(),
            stackOrientation: nil
        )
    }

    private func assertBoolViewInput<T: ViewInput>(_ type: T.Type) where T.Value == Bool {
        XCTAssertFalse(T.defaultValue)
    }
}
