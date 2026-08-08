import Foundation
import XCTest
@testable import VUI

private final class ViewAliasSourceRecorder {
    var remainingSourceCount = -1
    var styleableContextWasReset = false
    var sourceCountBeforePrimitiveLabel = -1
    var styleableContextType: Any.Type?
}

private struct ViewAliasSourceProbe: View, TestPrimitiveView {
    typealias Body = Never

    let recorder: ViewAliasSourceRecorder
    let size: CGSize

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ViewAliasSourceProbe._makeView called outside an active graph.")
        }
        let value = view._attribute.value
        var remaining = inputs.base[SourceInput<ButtonStyleConfiguration.Label>.self]
        var count = 0
        while remaining.pop() != nil {
            count += 1
        }
        value.recorder.remainingSourceCount = count
        value.recorder.styleableContextWasReset =
            inputs.base[StyleableViewContextInput.self] == nil
        let layout = graph.makeInput(value: LayoutComputer.fixed(value.size))
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct CanonicalRelayPrimitiveStyle: PrimitiveButtonStyle {
    let recorder: ViewAliasSourceRecorder

    func makeBody(configuration: Configuration) -> some View {
        CanonicalRelayProbeBody(
            configuration: configuration,
            recorder: recorder
        )
    }
}

private struct CanonicalRelayProbeBody: View, TestPrimitiveView {
    typealias Body = Never

    let configuration: PrimitiveButtonStyleConfiguration
    let recorder: ViewAliasSourceRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        let value = view._attribute.value
        var sources = inputs.base[
            SourceInput<ButtonStyleConfiguration.Label>.self
        ]
        var count = 0
        while sources.pop() != nil {
            count += 1
        }
        value.recorder.sourceCountBeforePrimitiveLabel = count
        value.recorder.styleableContextType =
            inputs.base[StyleableViewContextInput.self]
        return PrimitiveButtonStyleConfiguration.Label._makeView(
            view: view[\.configuration][\.label],
            inputs: inputs
        )
    }
}

final class ViewAliasSourceRoutingTests: XCTestCase {
    func testButtonBodyUsesCanonicalButtonStyleLabelSourceWriter() {
        let body = Button("Probe") {}.body
        let typeName = String(reflecting: type(of: body))

        XCTAssertTrue(
            typeName.contains("StaticSourceWriter<VUI.ButtonStyleConfiguration.Label")
        )
        XCTAssertFalse(
            typeName.contains("StaticSourceWriter<VUI.PrimitiveButtonStyleConfiguration.Label")
        )
    }

    func testResolvedButtonStyleBodyReentersThroughPrimitiveLabelButton() {
        let body = ResolvedButtonStyle(
            configuration: PrimitiveButtonStyleConfiguration(
                role: nil,
                label: PrimitiveButtonStyleConfiguration.Label(),
                action: .handler({})
            )
        ).body

        XCTAssertTrue(
            String(reflecting: type(of: body)).contains(
                "VUI.Button<VUI.PrimitiveButtonStyleConfiguration.Label>"
            )
        )
    }

    func testButtonStyleBodyReceivesPrimitiveRelayAndConcreteLabelSources() throws {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)

        try context.withCurrent {
            let recorder = ViewAliasSourceRecorder()
            let button = Button(action: {}) {
                ViewAliasSourceProbe(
                    recorder: recorder,
                    size: CGSize(width: 31, height: 17)
                )
            }
            .buttonStyle(CanonicalRelayPrimitiveStyle(recorder: recorder))
            let attribute = graph.makeInput(value: button)
            let outputs = makeView(
                view: _GraphValue(_attribute: attribute),
                inputs: makeViewInputs(graph: graph)
            )
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)

            XCTAssertEqual(recorder.sourceCountBeforePrimitiveLabel, 2)
            XCTAssertTrue(
                recorder.styleableContextType == ResolvedButtonStyle.self
            )
            XCTAssertEqual(recorder.remainingSourceCount, 0)
            XCTAssertTrue(recorder.styleableContextWasReset)
            XCTAssertEqual(
                layout.sizeThatFits(.unspecified),
                CGSize(width: 31, height: 17)
            )
        }
    }

    func testButtonStyleAliasPopsOneSourceAndResetsStyleableContext() throws {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)

        try context.withCurrent {
            let lowerRecorder = ViewAliasSourceRecorder()
            let upperRecorder = ViewAliasSourceRecorder()
            let lower = graph.makeInput(
                value: ViewAliasSourceProbe(
                    recorder: lowerRecorder,
                    size: CGSize(width: 11, height: 7)
                )
            )
            let upper = graph.makeInput(
                value: ViewAliasSourceProbe(
                    recorder: upperRecorder,
                    size: CGSize(width: 29, height: 13)
                )
            )
            let alias = graph.makeInput(value: ButtonStyleConfiguration.Label())
            var inputs = makeViewInputs(graph: graph)
            inputs.base.append(
                AnySource(value: _GraphValue(_attribute: lower)),
                to: SourceInput<ButtonStyleConfiguration.Label>.self
            )
            inputs.base.append(
                AnySource(value: _GraphValue(_attribute: upper)),
                to: SourceInput<ButtonStyleConfiguration.Label>.self
            )
            inputs.base[StyleableViewContextInput.self] = ViewAliasSourceProbe.self

            let outputs = ButtonStyleConfiguration.Label._makeView(
                view: _GraphValue(_attribute: alias),
                inputs: inputs
            )
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)

            XCTAssertEqual(
                layout.sizeThatFits(.unspecified),
                CGSize(width: 29, height: 13)
            )
            XCTAssertEqual(upperRecorder.remainingSourceCount, 1)
            XCTAssertTrue(upperRecorder.styleableContextWasReset)
            XCTAssertEqual(lowerRecorder.remainingSourceCount, -1)
        }
    }

    func testPrimitiveButtonLabelDelegatesToCanonicalAliasSource() throws {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)

        try context.withCurrent {
            let recorder = ViewAliasSourceRecorder()
            let source = graph.makeInput(
                value: ViewAliasSourceProbe(
                    recorder: recorder,
                    size: CGSize(width: 23, height: 9)
                )
            )
            let alias = graph.makeInput(
                value: PrimitiveButtonStyleConfiguration.Label()
            )
            var inputs = makeViewInputs(graph: graph)
            inputs.base.append(
                AnySource(value: _GraphValue(_attribute: source)),
                to: SourceInput<ButtonStyleConfiguration.Label>.self
            )

            let outputs = PrimitiveButtonStyleConfiguration.Label._makeView(
                view: _GraphValue(_attribute: alias),
                inputs: inputs
            )
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)

            XCTAssertEqual(
                layout.sizeThatFits(.unspecified),
                CGSize(width: 23, height: 9)
            )
            XCTAssertEqual(recorder.remainingSourceCount, 0)
        }
    }

    func testPlatformItemButtonStyleReadsConcreteLabelAfterPrimitiveRelay() throws {
        let button = Button(action: {}) {
            Label("Inspect", systemImage: "draw")
        }
        let content = button.modifier(
            PrimitiveButtonStyleContainerModifier(
                style: PlatformItemListButtonStyle()
            )
        )
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: type(of: content),
            content: content,
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            try AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let graph = viewGraph.data.graph
                let attribute = graph.makeInput(value: content)
                let generator: Attribute<PlatformItemList> =
                    graph.makeStatefulRule(
                        PlatformItemListGenerator<
                            AllPlatformItemListFlags,
                            ModifiedContent<
                                Button<Label<Text, Image>>,
                                PrimitiveButtonStyleContainerModifier<
                                    PlatformItemListButtonStyle
                                >
                            >
                        >(
                            content: attribute,
                            inputs: makeViewInputs(graph: graph),
                            inputsIncludeGeometry: false
                        )
                    )

                let item = try XCTUnwrap(
                    generator.value.buttonItems.first
                )
                XCTAssertEqual(item.label?.string, "Inspect")
                XCTAssertTrue(
                    item.namedResolvedImage != nil
                        || item.resolvedImage != nil
                )
            }
        }
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        return _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: environment,
                transaction: graph.makeInput(value: Transaction())
            ),
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
