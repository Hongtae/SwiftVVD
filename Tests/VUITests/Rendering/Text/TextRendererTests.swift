import XCTest
@testable import VUI

private struct TextRendererMarker: TextAttribute {
    var value: Int
}

private struct TextRendererSecondaryMarker: TextAttribute {
    var value: String
}

private struct TextRendererProbe: TextRenderer {
    var animatableData: Double = 0

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    }

    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        CGSize(width: proposal.width ?? 11, height: proposal.height ?? 7)
    }

    var displayPadding: EdgeInsets {
        EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
    }
}

final class TextRendererTests: XCTestCase {
    func testTextLayoutCarrierMatchesObservedMemoryAndCollectionSurface() {
        XCTAssertEqual(MemoryLayout<TextProxy>.size, 8)
        XCTAssertEqual(MemoryLayout<Text.Layout>.size, 24)
        XCTAssertEqual(MemoryLayout<Text.Layout.Line>.size, 44)
        XCTAssertEqual(MemoryLayout<Text.Layout.Run>.size, 48)
        XCTAssertEqual(MemoryLayout<Text.Layout.RunSlice>.size, 64)
        XCTAssertEqual(MemoryLayout<Text.Layout.CharacterIndex>.size, 8)
        XCTAssertEqual(MemoryLayout<Text.Layout.TypographicBounds>.size, 48)
        XCTAssertEqual(MemoryLayout<Text.Layout.DrawingOptions>.size, 4)
        XCTAssertEqual(Text.Layout.DrawingOptions.disablesSubpixelQuantization.rawValue, 1)

        let resolved = GraphicsContext.ResolvedText(runs: [], scaleFactor: 1)
        let layout = resolved.makeLayout(in: .zero, layoutDirection: .leftToRight)
        XCTAssertEqual(layout.startIndex, 0)
        XCTAssertEqual(layout.endIndex, 0)
        XCTAssertFalse(layout.isTruncated)
        XCTAssertEqual(
            Mirror(reflecting: layout).children.map { $0.label ?? "_" },
            ["lines", "isTruncated", "numberOfLines"]
        )

        let bounds = Text.Layout.TypographicBounds()
        XCTAssertEqual(bounds.origin, .zero)
        XCTAssertEqual(bounds.rect, .zero)
    }

    func testCustomTextAttributeReplacesSameTypeAndPreservesOtherTypes() {
        let text = Text(verbatim: "value")
            .customAttribute(TextRendererMarker(value: 1))
            .customAttribute(TextRendererSecondaryMarker(value: "kept"))
            .customAttribute(TextRendererMarker(value: 2))

        XCTAssertEqual(
            text.customAttributes.value(for: TextRendererMarker.self),
            TextRendererMarker(value: 2)
        )
        XCTAssertEqual(
            text.customAttributes.value(for: TextRendererSecondaryMarker.self),
            TextRendererSecondaryMarker(value: "kept")
        )
    }

    func testTextRendererModifierInstallsStatefulBoxInput() throws {
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            let modifier = _TextRendererViewModifier(
                renderer: TextRendererProbe(animatableData: 0.25)
            )
            let modifierAttribute = graph.makeInput(value: modifier)
            var inputs = makeViewInputs(graph: graph)

            type(of: modifier)._makeViewInputs(
                modifier: _GraphValue(_attribute: modifierAttribute),
                inputs: &inputs
            )

            let rendererAttribute = try XCTUnwrap(inputs[TextRendererInput.self].attribute)
            let box = rendererAttribute.value
            let resolved = GraphicsContext.ResolvedText(runs: [], scaleFactor: 1)
            XCTAssertEqual(
                box.sizeThatFits(proposal: .unspecified, text: TextProxy(ResolvedStyledText.TextLayoutManager(resolvedText: resolved))),
                CGSize(width: 11, height: 7)
            )
            XCTAssertEqual(
                box.displayPadding,
                EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
            )
            XCTAssertEqual(
                box.textLayoutBounds(
                    size: CGSize(width: 20, height: 10),
                    text: TextProxy(ResolvedStyledText.TextLayoutManager(resolvedText: resolved))
                ),
                CGRect(x: 0, y: 0, width: 20, height: 10)
            )
        }
    }

    // ASSERTIONS textRendererWeakInputObserved
    func testRendererInputExpiresWithItsSubgraphAndPreservesGenerationIdentity() throws {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        try context.withCurrent {
            var inputs = makeViewInputs(graph: graph)
            let subgraph = AGSubgraph()
            AGSubgraph.withCurrent(subgraph) {
                let modifier = _TextRendererViewModifier(renderer: TextRendererProbe())
                type(of: modifier)._makeViewInputs(
                    modifier: _GraphValue(_attribute: graph.makeInput(value: modifier)), inputs: &inputs)
            }
            let saved = inputs[TextRendererInput.self]
            let attribute = try XCTUnwrap(saved.attribute)
            XCTAssertTrue(TextRendererInput.valuesEqual(saved, inputs[TextRendererInput.self]))
            XCTAssertFalse(TextRendererInput.valuesEqual(saved, TextRendererInput.defaultValue))
            subgraph.invalidate()
            XCTAssertNil(saved.attribute)
            XCTAssertNil(saved.value)
            XCTAssertNil(inputs[TextRendererInput.self].value)

            let replacements = (0..<16).map { _ in graph.makeInput(value: TextRendererBoxBase()) }
            let replacement = try XCTUnwrap(replacements.first {
                $0.identifier.rawValue == attribute.identifier.rawValue
            })
            let reused = WeakAttribute(replacement)
            XCTAssertFalse(TextRendererInput.valuesEqual(saved, reused))
            XCTAssertTrue(TextRendererInput.valuesEqual(TextRendererInput.defaultValue, TextRendererInput.defaultValue))
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
