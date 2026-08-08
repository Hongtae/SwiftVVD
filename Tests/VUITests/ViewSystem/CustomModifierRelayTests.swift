import Foundation
import XCTest
@testable import VUI

private struct FixedRelaySource: View, TestPrimitiveView {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 42, height: 17))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct PlaceholderRelayResult<Source: View>: View {
    var body: some View {
        PlaceholderContentView<Source>()
    }
}

final class CustomModifierRelayTests: XCTestCase {
    func testCustomModifierRelaysPlaceholderToOriginalMakeViewBody() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            let view = FixedRelaySource().modifier(
                CustomModifier<FixedRelaySource, PlaceholderRelayResult<FixedRelaySource>>(
                    result: PlaceholderRelayResult()
                )
            )
            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 42, height: 17))
        }
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: environment,
            transaction: graph.makeInput(value: Transaction())
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
