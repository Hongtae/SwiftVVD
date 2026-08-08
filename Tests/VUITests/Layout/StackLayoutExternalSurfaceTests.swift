import XCTest
import VUI

private func genericStackOrientation<L: Layout>(_ type: L.Type) -> Axis? {
    L.layoutProperties.stackOrientation
}

private func stackLayoutRoute<L: Layout>(_ type: L.Type) -> String {
    "Layout"
}

private func stackLayoutRoute<L: Layout & _VariadicView_UnaryViewRoot>(
    _ type: L.Type
) -> String {
    "Layout+UnaryViewRoot"
}

final class StackLayoutExternalSurfaceTests: XCTestCase {
    func testPublicAndUnderscoredStackConformanceLevelsRemainDistinct() {
        XCTAssertEqual(stackLayoutRoute(HStackLayout.self), "Layout")
        XCTAssertEqual(stackLayoutRoute(VStackLayout.self), "Layout")
        XCTAssertEqual(
            stackLayoutRoute(_HStackLayout.self),
            "Layout+UnaryViewRoot"
        )
        XCTAssertEqual(
            stackLayoutRoute(_VStackLayout.self),
            "Layout+UnaryViewRoot"
        )
        XCTAssertEqual(stackLayoutRoute(ZStackLayout.self), "Layout")
        XCTAssertEqual(
            stackLayoutRoute(_ZStackLayout.self),
            "Layout+UnaryViewRoot"
        )

        XCTAssertNotEqual(
            ObjectIdentifier(HStackLayout.self),
            ObjectIdentifier(_HStackLayout.self)
        )
        XCTAssertNotEqual(
            ObjectIdentifier(VStackLayout.self),
            ObjectIdentifier(_VStackLayout.self)
        )
        XCTAssertNotEqual(
            ObjectIdentifier(ZStackLayout.self),
            ObjectIdentifier(_ZStackLayout.self)
        )
    }

    func testDerivedLayoutWitnessMatchesUnderscoredLayoutProperties() {
        XCTAssertEqual(
            genericStackOrientation(HStackLayout.self),
            .horizontal
        )
        XCTAssertEqual(
            genericStackOrientation(_HStackLayout.self),
            .horizontal
        )
        XCTAssertEqual(
            genericStackOrientation(VStackLayout.self),
            .vertical
        )
        XCTAssertEqual(
            genericStackOrientation(_VStackLayout.self),
            .vertical
        )
    }
}
