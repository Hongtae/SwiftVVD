import XCTest
@testable import VUI

private struct PreferredColorSchemeFallbackKey: PreferenceKey {
    static var defaultValue: Int { 0 }

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value = nextValue()
    }
}

private struct PreferredColorSchemeRetainedTraitKey: _ViewTraitKey {
    static var defaultValue: Int { 0 }
}

final class PreferredColorSchemeModifierTests: XCTestCase {
    func testPreviewContextRewritesInputsBeforeCallingBody() throws {
        // ASSERTIONS preferredColorSchemePreviewInputRewriteObserved
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            var inputs = makeViewListInputs(graph: graph)
            inputs.options.insert(.previewContext)
            inputs.base.changedDebugProperties = 0
            let originalEnvironmentBox = inputs.base.cachedEnvironment

            var traits = ViewTraitCollection()
            traits[PreferredColorSchemeRetainedTraitKey.self] = 17
            inputs._traits = OptionalAttribute(graph.makeInput(value: traits))

            let modifier = graph.makeInput(
                value: _PreferenceWritingModifier<PreferredColorSchemeKey>(
                    value: .dark
                )
            )
            var bodyInputs: _ViewListInputs?
            let expected = _ViewListOutputs(
                views: .staticList(.merged([])),
                nextImplicitID: 41,
                staticCount: 0
            )

            let outputs = _PreferenceWritingModifier<
                PreferredColorSchemeKey
            >._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, inputs in
                bodyInputs = inputs
                return expected
            }

            let rewritten = try XCTUnwrap(bodyInputs)
            XCTAssertFalse(
                rewritten.base.cachedEnvironment === originalEnvironmentBox
            )
            XCTAssertEqual(rewritten.base.changedDebugProperties, 0x20)
            XCTAssertEqual(
                rewritten.base.cachedEnvironment.value.environment.value.colorScheme,
                .dark
            )
            let rewrittenTraits = try XCTUnwrap(rewritten._traits.attribute).value
            XCTAssertEqual(
                rewrittenTraits[PreferredColorSchemeRetainedTraitKey.self],
                17
            )
            XCTAssertEqual(
                rewrittenTraits[PreviewColorSchemeTraitKey.self],
                .dark
            )
            XCTAssertEqual(outputs.nextImplicitID, expected.nextImplicitID)
            XCTAssertEqual(outputs.staticCount, expected.staticCount)
            guard case .staticList(.merged(let merged)) = outputs.views else {
                return XCTFail("Preview specialization must return body outputs directly.")
            }
            XCTAssertTrue(merged.isEmpty)

            modifier.setValue(
                _PreferenceWritingModifier<PreferredColorSchemeKey>(
                    value: .light
                )
            )
            XCTAssertEqual(
                rewritten.base.cachedEnvironment.value.environment.value.colorScheme,
                .light
            )
            XCTAssertEqual(
                rewritten._traits.attribute?.value[
                    PreviewColorSchemeTraitKey.self
                ],
                .light
            )
        }
    }

    func testPreferredColorSchemeWithoutPreviewContextUsesMultiViewList() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let inputs = makeViewListInputs(graph: graph)
            let originalEnvironmentBox = inputs.base.cachedEnvironment
            let modifier = graph.makeInput(
                value: _PreferenceWritingModifier<PreferredColorSchemeKey>(
                    value: .dark
                )
            )
            var bodyCallCount = 0

            let outputs = _PreferenceWritingModifier<
                PreferredColorSchemeKey
            >._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, inputs in
                bodyCallCount += 1
                XCTAssertTrue(
                    inputs.base.cachedEnvironment === originalEnvironmentBox
                )
                return self.emptyOutputs()
            }

            XCTAssertEqual(bodyCallCount, 1)
            guard case .staticList(.modified) = outputs.views else {
                return XCTFail("Non-preview path must use the multi-view modifier.")
            }
        }
    }

    func testOtherPreferenceKeysUseMultiViewListInPreviewContext() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var inputs = makeViewListInputs(graph: graph)
            inputs.options.insert(.previewContext)
            let originalEnvironmentBox = inputs.base.cachedEnvironment
            let modifier = graph.makeInput(
                value: _PreferenceWritingModifier<
                    PreferredColorSchemeFallbackKey
                >(value: 7)
            )
            var bodyCallCount = 0

            let outputs = _PreferenceWritingModifier<
                PreferredColorSchemeFallbackKey
            >._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, inputs in
                bodyCallCount += 1
                XCTAssertTrue(
                    inputs.base.cachedEnvironment === originalEnvironmentBox
                )
                return self.emptyOutputs()
            }

            XCTAssertEqual(bodyCallCount, 1)
            guard case .staticList(.modified) = outputs.views else {
                return XCTFail("Other keys must use the multi-view modifier.")
            }
        }
    }

    private func makeViewListInputs(graph: _AGGraph) -> _ViewListInputs {
        _ViewListInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: Phase()),
                environment: graph.makeInput(value: EnvironmentValues.tracking()),
                transaction: graph.makeInput(value: Transaction())
            ),
            implicitID: 0,
            options: [],
            _traits: OptionalAttribute(),
            traitKeys: nil,
            containerContext: nil,
            contentOffset: nil,
            debugReplaceableViewCount: nil
        )
    }

    private func emptyOutputs() -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.merged([])),
            nextImplicitID: 0,
            staticCount: 0
        )
    }
}
