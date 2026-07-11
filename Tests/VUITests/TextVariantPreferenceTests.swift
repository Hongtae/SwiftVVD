import XCTest
@testable import VUI

private final class TextVariantInputRecorder {
    var isEnabled: Bool?
}

private struct TextVariantInputRecorderContent: View, TestPrimitiveView {
    var recorder: TextVariantInputRecorder

    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        view._attribute.value.recorder.isEnabled = inputs.base[VariantThatFitsFlag.self]
        return _ViewOutputs()
    }
}

final class TextVariantPreferenceTests: XCTestCase {
    func testPreferenceCarriersMatchObservedEmptyLayout() {
        XCTAssertEqual(MemoryLayout<FixedTextVariant>.size, 0)
        XCTAssertEqual(MemoryLayout<FixedTextVariant>.stride, 1)
        XCTAssertEqual(MemoryLayout<SizeDependentTextVariant>.size, 0)
        XCTAssertEqual(MemoryLayout<SizeDependentTextVariant>.stride, 1)
        XCTAssertEqual(MemoryLayout<_TextVariantPreference<FixedTextVariant>>.size, 0)
        XCTAssertEqual(MemoryLayout<_TextVariantPreference<FixedTextVariant>>.stride, 1)
        XCTAssertEqual(MemoryLayout<_TextVariantPreference<SizeDependentTextVariant>>.size, 0)
        XCTAssertEqual(MemoryLayout<_TextVariantPreference<SizeDependentTextVariant>>.stride, 1)

        _ = Text("fixed").textVariant(.fixed)
        _ = Text("size dependent").textVariant(.sizeDependent)
    }

    func testFixedPreferenceLeavesVariantFlagDisabled() {
        let recorder = TextVariantInputRecorder()
        let content = FixedTextVariant()._preference.body(
            TextVariantInputRecorderContent(recorder: recorder)
        )

        makeView(content)

        XCTAssertEqual(recorder.isEnabled, false)
    }

    func testSizeDependentPreferenceEnablesVariantFlag() {
        let recorder = TextVariantInputRecorder()
        let content = SizeDependentTextVariant()._preference.body(
            TextVariantInputRecorderContent(recorder: recorder)
        )

        makeView(content)

        XCTAssertEqual(recorder.isEnabled, true)
    }

    private func makeView<Content>(_ content: Content) where Content: View {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let view = graph.makeInput(value: content)
            _ = Content._makeView(
                view: _GraphValue(_attribute: view),
                inputs: makeViewInputs(graph: graph)
            )
        }
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        return _ViewInputs(
            base: _GraphInputs(
                customInputs: PropertyList(),
                time: graph.makeInput(value: Time(seconds: 0)),
                cachedEnvironment: MutableBox(CachedEnvironment(environment: environment)),
                phase: graph.makeInput(value: Phase()),
                transaction: graph.makeInput(value: Transaction()),
                changedDebugProperties: 0,
                options: [],
                mergedInputs: []
            ),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: .zero),
            containerPosition: graph.makeInput(value: .zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
