import XCTest
@testable import VUI

final class LayoutProxyPlacementContextTests: XCTestCase {
    func testLayoutProxyUsesExplicitOwnerOutsideRuleEvaluation() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let owner = graph.makeInput(value: 0)
            let layoutComputer = LayoutComputer.fixed(CGSize(width: 12, height: 34))
            let layoutComputerAttr = graph.makeInput(value: layoutComputer)
            let attributes = LayoutProxyAttributes(layoutComputer: layoutComputerAttr)

            XCTAssertNil(_AGGraph.currentRuleContextAttribute)
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: attributes
            )

            XCTAssertEqual(proxy.context.attribute, owner.identifier)
            XCTAssertNotEqual(proxy.context.attribute, layoutComputerAttr.identifier)
            let subview = LayoutSubview(proxy: proxy)
            XCTAssertEqual(subview.sizeThatFits(.unspecified), CGSize(width: 12, height: 34))
        }
    }

    func testLayoutProxyTraitReadInvalidatesItsExplicitOwner() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let recorder = LayoutProxyTraitEvaluationRecorder()
            let traitsList = graph.makeInput(
                value: makeLayoutProxyTraitList(value: 11)
            )
            let output: Attribute<Int> = graph.makeRule {
                guard let owner = _AGGraph.currentRuleContextAttribute else {
                    fatalError("test rule requires an active context")
                }
                recorder.evaluationCount += 1
                let proxy = LayoutProxy(
                    context: AnyRuleContext(attribute: owner),
                    attributes: LayoutProxyAttributes(
                        traitsList: OptionalAttribute(traitsList)
                    )
                )
                return proxy[_LayoutTrait<LayoutProxyTestValueKey>.self]
            }

            XCTAssertEqual(output.value, 11)
            XCTAssertEqual(recorder.evaluationCount, 1)

            traitsList.value = makeLayoutProxyTraitList(value: 37)

            XCTAssertEqual(output.value, 37)
            XCTAssertEqual(recorder.evaluationCount, 2)
        }
    }

    func testPaddingPlacementPreservesUnspecifiedProposalAxes() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let owner = graph.makeInput(value: 0)
            let environment = graph.makeInput(value: EnvironmentValues())
            let layoutComputer = graph.makeInput(
                value: LayoutComputer.fixed(CGSize(width: 12, height: 34))
            )
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(
                    layoutComputer: layoutComputer
                )
            )
            let layout = _PaddingLayout(
                edges: .all,
                insets: EdgeInsets(_all: 4)
            )

            let placement = layout.placement(
                of: proxy,
                in: PlacementContext(
                    context: AnyRuleContext(attribute: owner.identifier),
                    owner: owner.identifier,
                    environment: environment,
                    parentSize: ViewSize(
                        CGSize(width: 120, height: 60),
                        proposal: _ProposedSize(width: 100, height: nil)
                    )
                )
            )

            XCTAssertEqual(placement.proposedSize_.width, 92)
            XCTAssertNil(placement.proposedSize_.height)
            XCTAssertEqual(placement.anchor, .topLeading)
            XCTAssertEqual(placement.anchorPosition, CGPoint(x: 4, y: 4))
        }
    }

    func testDefaultPaddingEnvironmentRouteAndCachedGraphInput() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let environment = graph.makeInput(value: EnvironmentValues())
            let inputs = _GraphInputs(
                time: graph.makeInput(value: Time()),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: environment,
                transaction: graph.makeInput(value: Transaction())
            )

            let first = inputs.defaultPadding
            let second = inputs.defaultPadding
            XCTAssertEqual(first.identifier, second.identifier)
            XCTAssertEqual(first.value, EdgeInsets(_all: 16))

            var values = EnvironmentValues()
            values.defaultPadding = EdgeInsets(
                top: 2,
                leading: 3,
                bottom: 5,
                trailing: 7
            )
            environment.value = values
            XCTAssertEqual(first.value, values.defaultPadding)
        }
    }

    func testPaddingUsesEnvironmentInsetsForSizeAndPlacement() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let owner = graph.makeInput(value: 0)
            var values = EnvironmentValues()
            values.defaultPadding = EdgeInsets(
                top: 2,
                leading: 3,
                bottom: 5,
                trailing: 7
            )
            let environment = graph.makeInput(value: values)
            let recorder = LayoutProposalRecorder()
            let layoutComputer = graph.makeInput(value: testLayoutComputer {
                recorder.proposals.append($0)
                return CGSize(width: 40, height: 30)
            })
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(
                    layoutComputer: layoutComputer
                )
            )
            let layout = _PaddingLayout(edges: .all, insets: nil)
            let sizeContext = SizeAndSpacingContext(
                context: AnyRuleContext(attribute: owner.identifier),
                owner: owner.identifier,
                environment: environment
            )

            XCTAssertEqual(
                layout.sizeThatFits(
                    in: _ProposedSize(width: 100, height: 80),
                    context: sizeContext,
                    child: proxy
                ),
                CGSize(width: 50, height: 37)
            )
            XCTAssertEqual(recorder.proposals.last?.width, 90)
            XCTAssertEqual(recorder.proposals.last?.height, 73)

            let placement = layout.placement(
                of: proxy,
                in: PlacementContext(
                    context: AnyRuleContext(attribute: owner.identifier),
                    owner: owner.identifier,
                    environment: environment,
                    parentSize: ViewSize(
                        CGSize(width: 100, height: 80),
                        proposal: _ProposedSize(width: 100, height: 80)
                    )
                )
            )
            XCTAssertEqual(placement.proposedSize_.width, 90)
            XCTAssertEqual(placement.proposedSize_.height, 73)
            XCTAssertEqual(placement.anchor, .topLeading)
            XCTAssertEqual(placement.anchorPosition, CGPoint(x: 3, y: 2))
            XCTAssertTrue(layout.ignoresAutomaticPadding(child: proxy))
        }
    }

    func testPaddingClampsNegativeWrapperSizeToZero() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let owner = graph.makeInput(value: 0)
            let environment = graph.makeInput(value: EnvironmentValues())
            let layoutComputer = graph.makeInput(value: testLayoutComputer { _ in
                CGSize(width: 40, height: 30)
            })
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(layoutComputer: layoutComputer)
            )
            let layout = _PaddingLayout(
                edges: .all,
                insets: EdgeInsets(_all: -30)
            )

            XCTAssertEqual(
                layout.sizeThatFits(
                    in: _ProposedSize(width: 100, height: 80),
                    context: SizeAndSpacingContext(
                        context: AnyRuleContext(attribute: owner.identifier),
                        owner: owner.identifier,
                        environment: environment
                    ),
                    child: proxy
                ),
                .zero
            )
        }
    }

    func testPaddingResetsOnlyInsetSpacingEdgesUsingLayoutDirection() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let owner = graph.makeInput(value: 0)
            var values = EnvironmentValues()
            values.layoutDirection = .rightToLeft
            let environment = graph.makeInput(value: values)
            let childSpacing = Spacing(minima: [
                Spacing.Key(category: .default, edge: .left): .distance(11),
                Spacing.Key(category: .edgeRightText, edge: .left): .distance(13),
                Spacing.Key(category: .default, edge: .right): .distance(17),
                Spacing.Key(category: .edgeLeftText, edge: .right): .distance(19),
            ])
            let layoutComputer = graph.makeInput(value: testLayoutComputer(
                sizeThatFits: { _ in .zero },
                spacing: childSpacing
            ))
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(layoutComputer: layoutComputer)
            )
            let layout = _PaddingLayout(
                edges: .leading,
                insets: EdgeInsets(_all: 4)
            )
            let context = SizeAndSpacingContext(
                context: AnyRuleContext(attribute: owner.identifier),
                owner: owner.identifier,
                environment: environment
            )
            var expected = childSpacing
            expected.reset(.right)

            XCTAssertEqual(
                layout.spacing(in: context, child: proxy),
                expected
            )
        }
    }

    func testFixedSizePlacementMasksRawProposalWithoutRemeasuring() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let owner = graph.makeInput(value: 0)
            let environment = graph.makeInput(value: EnvironmentValues())
            let recorder = LayoutMeasurementRecorder()
            let layoutComputer = graph.makeInput(value: testLayoutComputer { _ in
                recorder.count += 1
                return CGSize(width: 40, height: 30)
            })
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(layoutComputer: layoutComputer)
            )
            let placement = _FixedSizeLayout(horizontal: true, vertical: false)
                .placement(
                    of: proxy,
                    in: PlacementContext(
                        context: AnyRuleContext(attribute: owner.identifier),
                        owner: owner.identifier,
                        environment: environment,
                        parentSize: ViewSize(
                            CGSize(width: 120, height: 60),
                            proposal: _ProposedSize(width: 100, height: 50)
                        )
                    )
                )

            XCTAssertEqual(recorder.count, 0)
            XCTAssertNil(placement.proposedSize_.width)
            XCTAssertEqual(placement.proposedSize_.height, 50)
            XCTAssertEqual(placement.anchor, .center)
            XCTAssertEqual(placement.anchorPosition, CGPoint(x: 60, y: 30))
        }
    }

    func testLayoutPriorityPlacementPreservesRawProposalWithoutRemeasuring() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let owner = graph.makeInput(value: 0)
            let environment = graph.makeInput(value: EnvironmentValues())
            let recorder = LayoutMeasurementRecorder()
            let layoutComputer = graph.makeInput(value: testLayoutComputer { _ in
                recorder.count += 1
                return CGSize(width: 40, height: 30)
            })
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(layoutComputer: layoutComputer)
            )
            let placement = LayoutPriorityLayout(value: 3).placement(
                of: proxy,
                in: PlacementContext(
                    context: AnyRuleContext(attribute: owner.identifier),
                    owner: owner.identifier,
                    environment: environment,
                    parentSize: ViewSize(
                        CGSize(width: 120, height: 60),
                        proposal: _ProposedSize(width: nil, height: 50)
                    )
                )
            )

            XCTAssertEqual(recorder.count, 0)
            XCTAssertNil(placement.proposedSize_.width)
            XCTAssertEqual(placement.proposedSize_.height, 50)
            XCTAssertEqual(placement.anchor, .center)
            XCTAssertEqual(placement.anchorPosition, CGPoint(x: 60, y: 30))
        }
    }
}

private struct LayoutProxyTestValueKey: LayoutValueKey {
    static let defaultValue = -1
}

private final class LayoutProxyTraitEvaluationRecorder {
    var evaluationCount = 0
}

private final class LayoutProposalRecorder {
    var proposals: [_ProposedSize] = []
}

private final class LayoutMeasurementRecorder {
    var count = 0
}

private func makeLayoutProxyTraitList(value: Int) -> any ViewList {
    var traits = ViewTraitCollection()
    traits[_LayoutTrait<LayoutProxyTestValueKey>.self] = value
    return BaseViewList(
        elements: EmptyViewListElements(),
        traits: traits
    )
}
