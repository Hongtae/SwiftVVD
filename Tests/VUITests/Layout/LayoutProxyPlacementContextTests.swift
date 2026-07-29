import XCTest
@testable import VUI

final class LayoutProxyPlacementContextTests: XCTestCase {
    func testLayoutProxyCanBeCreatedForPlacementOutsideRuleEvaluation() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            _ = graph.makeInput(value: 0)
            let layoutComputer = LayoutComputer.fixed(CGSize(width: 12, height: 34))
            let layoutComputerAttr = graph.makeInput(value: layoutComputer)
            let attributes = LayoutProxyAttributes(layoutComputer: layoutComputerAttr)

            XCTAssertNil(_AGGraph.currentRuleContextAttribute)
            let proxy = LayoutProxy(attributes: attributes)

            XCTAssertEqual(proxy.context.attribute, layoutComputerAttr.identifier)
            let subview = LayoutSubview(proxy: proxy)
            XCTAssertEqual(subview.sizeThatFits(.unspecified), CGSize(width: 12, height: 34))
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
