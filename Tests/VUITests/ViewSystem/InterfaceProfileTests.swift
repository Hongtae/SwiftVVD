import XCTest
@testable import VUI

final class InterfaceProfileTests: XCTestCase {
    func testProfileSurfaceUsesGenericDesignerFacingNames() {
        XCTAssertEqual(
            Set(InterfaceProfile.allCases),
            [.desktop, .mobile, .tablet, .handheld, .vr]
        )
    }

    func testEnvironmentUsesDesktopDefaultAndStoresExplicitSelection() {
        var values = EnvironmentValues()

        XCTAssertEqual(values.interfaceProfile, .desktop)

        values.interfaceProfile = .handheld

        XCTAssertEqual(values.interfaceProfile, .handheld)
        XCTAssertEqual(
            Environment(\.interfaceProfile)._resolve(values).wrappedValue,
            .handheld
        )
    }

    func testEnvironmentModifierPublishesProfileThroughGraphInputs() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var inputs = makeGraphInputs(graph: graph)
            let modifier = graph.makeInput(
                value: _EnvironmentKeyWritingModifier(
                    keyPath: \.interfaceProfile,
                    value: InterfaceProfile.vr
                )
            )

            _EnvironmentKeyWritingModifier<InterfaceProfile>._makeInputs(
                modifier: _GraphValue(_attribute: modifier),
                inputs: &inputs
            )

            XCTAssertEqual(
                inputs.cachedEnvironment.value.environment.value.interfaceProfile,
                .vr
            )
        }
    }

    private func makeGraphInputs(graph: _AGGraph) -> _GraphInputs {
        _GraphInputs(
            time: graph.makeInput(value: Time()),
            phase: graph.makeInput(value: Phase()),
            environment: graph.makeInput(value: EnvironmentValues.tracking()),
            transaction: graph.makeInput(value: Transaction())
        )
    }
}
