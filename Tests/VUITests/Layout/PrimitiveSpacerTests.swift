import XCTest
@testable import VUI

private enum SpacerRepresentationProbe: PlatformSpacerRepresentable {
    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool {
        true
    }

    static func makeRepresentation(
        inputs: _ViewInputs,
        outputs: inout _ViewOutputs
    ) {
        outputs._layoutComputer = OptionalAttribute()
    }
}

private func isPrimitiveSpacerView(_ type: Any.Type) -> Bool {
    type is any PrimitiveView.Type
}

private func isUnarySpacerView(_ type: Any.Type) -> Bool {
    type is any UnaryView.Type
}

private func spacingDistance(_ spacing: Spacing, at edge: AbsoluteEdge) -> CGFloat? {
    spacing.minima[Spacing.Key(category: .default, edge: edge)]?.value
}

private func spacingDistance(
    _ spacing: Spacing,
    category: Spacing.Category,
    edge: AbsoluteEdge
) -> CGFloat? {
    spacing.minima[Spacing.Key(category: category, edge: edge)]?.value
}

final class PrimitiveSpacerTests: XCTestCase {
    func testSpacerUsesInheritedStackOrientationAndDefaultMinimum() {
        withGraph { graph in
            let horizontal = makeLayoutComputer(
                Spacer(),
                graph: graph,
                stackOrientation: .horizontal
            )
            XCTAssertEqual(horizontal.sizeThatFits(.unspecified), CGSize(width: 8, height: 0))
            XCTAssertEqual(
                horizontal.sizeThatFits(_ProposedSize(width: 100, height: 50)),
                CGSize(width: 100, height: 0)
            )
            XCTAssertEqual(horizontal.layoutPriority(), -.infinity)
            XCTAssertTrue(horizontal.box.requiresSpacingProjection())
            XCTAssertEqual(spacingDistance(horizontal.spacing(), at: .left), 0)
            XCTAssertEqual(spacingDistance(horizontal.spacing(), at: .right), 0)
            XCTAssertNil(spacingDistance(horizontal.spacing(), at: .top))
            XCTAssertNil(spacingDistance(horizontal.spacing(), at: .bottom))

            let vertical = makeLayoutComputer(
                Spacer(),
                graph: graph,
                stackOrientation: .vertical
            )
            XCTAssertEqual(vertical.sizeThatFits(.unspecified), CGSize(width: 0, height: 8))
            XCTAssertEqual(
                vertical.sizeThatFits(_ProposedSize(width: 100, height: 50)),
                CGSize(width: 0, height: 50)
            )

            let neutral = makeLayoutComputer(
                Spacer(),
                graph: graph,
                stackOrientation: nil
            )
            XCTAssertEqual(neutral.sizeThatFits(.unspecified), CGSize(width: 8, height: 8))
            XCTAssertEqual(
                neutral.sizeThatFits(_ProposedSize(width: 100, height: 50)),
                CGSize(width: 100, height: 50)
            )
        }
    }

    func testSpacerUsesExplicitMinimumAndDynamicOrientation() {
        withGraph { graph in
            let horizontal = makeLayoutComputer(
                Spacer(minLength: 12),
                graph: graph,
                stackOrientation: nil,
                dynamicOrientation: .horizontal
            )
            XCTAssertEqual(horizontal.sizeThatFits(.unspecified), CGSize(width: 12, height: 0))
            XCTAssertEqual(
                horizontal.sizeThatFits(_ProposedSize(width: 4, height: 50)),
                CGSize(width: 12, height: 0)
            )

            let vertical = makeLayoutComputer(
                Spacer(minLength: 12),
                graph: graph,
                stackOrientation: nil,
                dynamicOrientation: .vertical
            )
            XCTAssertEqual(vertical.sizeThatFits(.unspecified), CGSize(width: 0, height: 12))
        }
    }

    func testFixedAxisSpacerFamiliesIgnoreInheritedOrientation() {
        withGraph { graph in
            let horizontal = makeLayoutComputer(
                _HSpacer(minWidth: 12),
                graph: graph,
                stackOrientation: .vertical
            )
            XCTAssertEqual(horizontal.sizeThatFits(.unspecified), CGSize(width: 12, height: 0))
            XCTAssertEqual(
                horizontal.sizeThatFits(_ProposedSize(width: 100, height: 50)),
                CGSize(width: 100, height: 0)
            )

            let vertical = makeLayoutComputer(
                _VSpacer(minHeight: 12),
                graph: graph,
                stackOrientation: .horizontal
            )
            XCTAssertEqual(vertical.sizeThatFits(.unspecified), CGSize(width: 0, height: 12))
            XCTAssertEqual(
                vertical.sizeThatFits(_ProposedSize(width: 100, height: 50)),
                CGSize(width: 0, height: 50)
            )
        }
    }

    func testTextBaselineRelativeSpacerUsesDynamicAxisSizing() {
        withGraph { graph in
            let horizontal = makeLayoutComputer(
                _TextBaselineRelativeSpacer(minLength: 12),
                graph: graph,
                stackOrientation: .horizontal
            )
            XCTAssertEqual(horizontal.sizeThatFits(.unspecified), CGSize(width: 12, height: 0))
            let horizontalSpacing = horizontal.spacing()
            XCTAssertEqual(horizontalSpacing.minima.count, 4)
            XCTAssertEqual(spacingDistance(horizontalSpacing, at: .left), 0)
            XCTAssertEqual(spacingDistance(horizontalSpacing, at: .right), 0)
            XCTAssertEqual(
                spacingDistance(
                    horizontalSpacing,
                    category: .leftTextBaseline,
                    edge: .left
                ),
                0
            )
            XCTAssertEqual(
                spacingDistance(
                    horizontalSpacing,
                    category: .rightTextBaseline,
                    edge: .right
                ),
                0
            )

            let vertical = makeLayoutComputer(
                _TextBaselineRelativeSpacer(minLength: 12),
                graph: graph,
                stackOrientation: .vertical
            )
            XCTAssertEqual(vertical.sizeThatFits(.unspecified), CGSize(width: 0, height: 12))
            let verticalSpacing = vertical.spacing()
            XCTAssertEqual(verticalSpacing.minima.count, 4)
            XCTAssertEqual(spacingDistance(verticalSpacing, at: .top), 0)
            XCTAssertEqual(spacingDistance(verticalSpacing, at: .bottom), 0)
            XCTAssertEqual(
                spacingDistance(
                    verticalSpacing,
                    category: .textBaseline,
                    edge: .top
                ),
                0
            )
            XCTAssertEqual(
                spacingDistance(
                    verticalSpacing,
                    category: .textBaseline,
                    edge: .bottom
                ),
                0
            )

            let neutral = makeLayoutComputer(
                _TextBaselineRelativeSpacer(minLength: 12),
                graph: graph,
                stackOrientation: nil
            )
            let neutralSpacing = neutral.spacing()
            XCTAssertEqual(neutralSpacing.minima.count, 4)
            XCTAssertNil(
                spacingDistance(
                    neutralSpacing,
                    category: .textBaseline,
                    edge: .top
                )
            )
        }
    }

    func testDisabledConditionalSpacerDoesNotProjectSpacing() {
        withGraph { graph in
            let disabled = makeLayoutComputer(
                ConditionalSpacer(isEnabled: false, minLength: 12),
                graph: graph,
                stackOrientation: .horizontal
            )
            XCTAssertEqual(disabled.sizeThatFits(.unspecified), .zero)
            XCTAssertFalse(disabled.box.requiresSpacingProjection())
            XCTAssertNil(spacingDistance(disabled.spacing(), at: .left))
            XCTAssertNil(spacingDistance(disabled.spacing(), at: .right))

            let enabled = makeLayoutComputer(
                ConditionalSpacer(isEnabled: true, minLength: 12),
                graph: graph,
                stackOrientation: .horizontal
            )
            XCTAssertEqual(enabled.sizeThatFits(.unspecified), CGSize(width: 12, height: 0))
            XCTAssertTrue(enabled.box.requiresSpacingProjection())
        }
    }

    func testSpacerRepresentationProviderCanReplacePrimitiveOutput() {
        withGraph { graph in
            var inputs = makeViewInputs(graph: graph, stackOrientation: nil)
            inputs.requestedSpacerRepresentation = SpacerRepresentationProbe.self
            let spacer = graph.makeInput(value: Spacer())
            let outputs = Spacer._makeView(
                view: _GraphValue(_attribute: spacer),
                inputs: inputs
            )
            XCTAssertNil(outputs._layoutComputer.attribute)
        }
    }

    func testSpacerFamilyUsesObservedPrimitiveRoles() {
        XCTAssertTrue(isPrimitiveSpacerView(Spacer.self))
        XCTAssertTrue(isUnarySpacerView(Spacer.self))
        XCTAssertTrue(isPrimitiveSpacerView(_HSpacer.self))
        XCTAssertTrue(isUnarySpacerView(_HSpacer.self))
        XCTAssertTrue(isPrimitiveSpacerView(_VSpacer.self))
        XCTAssertTrue(isUnarySpacerView(_VSpacer.self))
        XCTAssertTrue(isPrimitiveSpacerView(_TextBaselineRelativeSpacer.self))
        XCTAssertTrue(isUnarySpacerView(_TextBaselineRelativeSpacer.self))
        XCTAssertTrue(isPrimitiveSpacerView(ConditionalSpacer.self))
        XCTAssertTrue(isUnarySpacerView(ConditionalSpacer.self))
    }

    private func withGraph(_ body: (_AGGraph) -> Void) {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        context.withCurrent {
            body(graph)
        }
    }

    private func makeLayoutComputer<S: PrimitiveSpacer>(
        _ spacer: S,
        graph: _AGGraph,
        stackOrientation: Axis?,
        dynamicOrientation: Axis? = nil
    ) -> LayoutComputer {
        var inputs = makeViewInputs(
            graph: graph,
            stackOrientation: stackOrientation
        )
        if let dynamicOrientation {
            inputs[DynamicStackOrientation.self] = OptionalAttribute(
                graph.makeInput(value: Optional(dynamicOrientation))
            )
        }
        let attribute = graph.makeInput(value: spacer)
        let outputs = S._makeView(
            view: _GraphValue(_attribute: attribute),
            inputs: inputs
        )
        return try! XCTUnwrap(outputs._layoutComputer.attribute).value
    }

    private func makeViewInputs(
        graph: _AGGraph,
        stackOrientation: Axis?
    ) -> _ViewInputs {
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
            stackOrientation: stackOrientation
        )
    }
}
