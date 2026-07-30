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
}

private struct LayoutProxyTestValueKey: LayoutValueKey {
    static let defaultValue = -1
}

private final class LayoutProxyTraitEvaluationRecorder {
    var evaluationCount = 0
}

private func makeLayoutProxyTraitList(value: Int) -> any ViewList {
    var traits = ViewTraitCollection()
    traits[_LayoutTrait<LayoutProxyTestValueKey>.self] = value
    return BaseViewList(
        elements: EmptyViewListElements(),
        traits: traits
    )
}
