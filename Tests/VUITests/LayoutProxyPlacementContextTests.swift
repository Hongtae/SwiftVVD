import XCTest
@testable import VUI

final class LayoutProxyPlacementContextTests: XCTestCase {
    func testLayoutProxyCanBeCreatedForPlacementOutsideRuleEvaluation() {
        let graph = AttributeGraph()

        AttributeGraph.withCurrent(graph) {
            _ = graph.makeInput(value: 0)
            let layoutComputer = LayoutComputer.fixed(CGSize(width: 12, height: 34))
            let layoutComputerAttr = graph.makeInput(value: layoutComputer)
            let attributes = LayoutProxyAttributes(layoutComputer: layoutComputerAttr)

            XCTAssertNil(AttributeGraph.currentRuleContextAttribute)
            let proxy = LayoutProxy(attributes: attributes)

            XCTAssertNil(proxy.context)
            let subview = LayoutSubview(proxy: proxy)
            XCTAssertEqual(subview.sizeThatFits(.unspecified), CGSize(width: 12, height: 34))
        }
    }
}
