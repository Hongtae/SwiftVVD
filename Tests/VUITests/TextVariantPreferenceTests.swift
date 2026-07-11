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

private struct TextVariantTestLayoutEngine: LayoutEngine {
    var marker: Int

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: marker, height: marker)
    }
}

private struct TextVariantTestResolver: SizeFittingTextResolver {
    typealias Input = Int
    typealias Engine = TextVariantTestLayoutEngine

    var sizeVariant: TextSizeVariant

    var narrowerVariant: TextVariantTestResolver {
        TextVariantTestResolver(sizeVariant: sizeVariant.nextDown)
    }

    func value(for input: Int) -> SizeFittingTextCacheValue<TextVariantTestLayoutEngine> {
        SizeFittingTextCacheValue(
            text: ResolvedStyledText(),
            engine: TextVariantTestLayoutEngine(marker: input),
            renderer: nil
        )
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

    func testTextSizeVariantRawValuesAndTraversalMatchObservedOrder() {
        XCTAssertEqual(TextSizeVariant.regular.rawValue, 0)
        XCTAssertEqual(TextSizeVariant.compact.rawValue, 1)
        XCTAssertEqual(TextSizeVariant.small.rawValue, 2)
        XCTAssertEqual(TextSizeVariant.tiny.rawValue, 3)
        XCTAssertNil(TextSizeVariant.regular.nextUp)
        XCTAssertEqual(TextSizeVariant.compact.nextUp, .regular)
        XCTAssertEqual(TextSizeVariant.regular.nextDown, .compact)
        XCTAssertEqual(TextSizeVariant.compact.nextDown, .small)
    }

    func testStickyLogicDefaultsKeepVerticalGrowthAndReleaseHorizontalGrowth() {
        var logic = StickyTextSizeFittingLogic()
        XCTAssertFalse(logic.stickOnHorizontalGrowth)
        XCTAssertTrue(logic.stickOnVerticalGrowth)
        XCTAssertNil(logic.suggestedVariant(for: .unspecified))

        logic.commit(.regular, for: ProposedViewSize(width: 100, height: 40))
        XCTAssertEqual(
            logic.suggestedVariant(for: ProposedViewSize(width: 90, height: 60)),
            .regular
        )
        XCTAssertNil(
            logic.suggestedVariant(for: ProposedViewSize(width: 110, height: 40))
        )

        logic.onInvalidation(of: .compact)
        XCTAssertNotNil(logic.committedValue)
        logic.onInvalidation(of: .regular)
        XCTAssertNil(logic.committedValue)
    }

    func testOneEntryCacheKeepsRegularVariantAndInvalidatesResolvedValueOnInputChange() {
        let cache = SizeFittingTextCache(
            resolver: TextVariantTestResolver(sizeVariant: .regular),
            logic: StickyTextSizeFittingLogic(),
            input: 10
        )

        XCTAssertEqual(cache.sizeVariantCache.capacity, 10)
        XCTAssertFalse(cache.exhaustedWidthVariants)
        XCTAssertEqual(cache.resultCache.count, 1)
        XCTAssertEqual(
            cache.sizeVariant(for: ProposedViewSize(width: 50, height: 50)),
            .regular
        )
        XCTAssertEqual(
            cache.withValue(for: ProposedViewSize(width: 50, height: 50)) {
                $0.engine.marker
            },
            10
        )

        cache.setInput(20, changed: false)
        XCTAssertEqual(cache.withValue(for: .unspecified) { $0.engine.marker }, 10)
        cache.setInput(20, changed: true)
        XCTAssertEqual(cache.withValue(for: .unspecified) { $0.engine.marker }, 20)
    }

    func testTextMakeViewUsesDedicatedSizeFittingLayoutEngineOnlyWhenFlagIsEnabled() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let view = graph.makeInput(value: Text("variant"))

            var ordinaryInputs = makeViewInputs(graph: graph)
            ordinaryInputs.base[VariantThatFitsFlag.self] = false
            let ordinary = Text._makeView(
                view: _GraphValue(_attribute: view),
                inputs: ordinaryInputs
            )
            let ordinaryComputer = ordinary._layoutComputer.attribute!.value
            XCTAssertTrue(ordinaryComputer.box is LayoutEngineBox<ClosureLayoutEngine>)

            var sizeDependentInputs = makeViewInputs(graph: graph)
            sizeDependentInputs.base[VariantThatFitsFlag.self] = true
            let sizeDependent = Text._makeView(
                view: _GraphValue(_attribute: view),
                inputs: sizeDependentInputs
            )
            let sizeDependentComputer = sizeDependent._layoutComputer.attribute!.value
            XCTAssertTrue(
                sizeDependentComputer.box is LayoutEngineBox<SizeFittingTextLayoutComputer.Engine>
            )
            XCTAssertEqual(sizeDependentComputer.sizeThatFits(.unspecified), .zero)
        }
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
