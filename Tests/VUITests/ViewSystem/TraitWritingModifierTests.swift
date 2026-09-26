import XCTest
@testable import VUI

private struct TraitWritingModifierTestKey: _ViewTraitKey {
    static var defaultValue: Int { 0 }
}

final class TraitWritingModifierTests: XCTestCase {
    // ASSERTIONS: listSectionInputTraitTracking27Observed
    func testStaticBodyConversionPreservesMetadataAndLiveTraitAttribute() throws {
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            let inputs = makeViewListInputs(graph: graph)
            let modifier = graph.makeInput(
                value: _TraitWritingModifier<TraitWritingModifierTestKey>(
                    value: 17
                )
            )
            var bodyTraits: Attribute<ViewTraitCollection>?

            let outputs = _TraitWritingModifier<
                TraitWritingModifierTestKey
            >._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, inputs in
                bodyTraits = inputs._traits.attribute
                return _ViewListOutputs(
                    views: .staticList(.merged([])),
                    nextImplicitID: 41,
                    staticCount: 3
                )
            }

            XCTAssertEqual(try XCTUnwrap(bodyTraits).value[
                TraitWritingModifierTestKey.self
            ], 17)
            XCTAssertEqual(outputs.nextImplicitID, 41)
            XCTAssertEqual(outputs.staticCount, 3)

            guard case .dynamicList(let list, let listModifier) =
                    outputs.views else {
                return XCTFail("A static trait-writing body must become an attribute-backed list.")
            }
            XCTAssertNil(listModifier)
            XCTAssertEqual(
                list.value.traits[TraitWritingModifierTestKey.self],
                17
            )

            modifier.setValue(
                _TraitWritingModifier<TraitWritingModifierTestKey>(value: 29)
            )
            XCTAssertEqual(
                list.value.traits[TraitWritingModifierTestKey.self],
                29
            )
        }
    }

    private func makeViewListInputs(graph: _AGGraph) -> _ViewListInputs {
        _ViewListInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(
                    value: EnvironmentValues.tracking()
                ),
                transaction: graph.makeInput(value: Transaction())
            ),
            implicitID: 7,
            options: [],
            _traits: OptionalAttribute(),
            traitKeys: ViewTraitKeys(),
            containerContext: nil,
            contentOffset: nil,
            debugReplaceableViewCount: nil
        )
    }
}
