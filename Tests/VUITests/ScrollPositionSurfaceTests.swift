import CoreGraphics
import XCTest
@testable import VUI

final class ScrollPositionSurfaceTests: XCTestCase {
    private func mirrorDigest(_ value: ScrollPosition) -> String {
        Mirror(reflecting: value).children.map { child in
            "\(child.label ?? "_")=\(String(describing: child.value))"
        }.joined(separator: ", ")
    }

    func testStorageLabelsAndInitializersMatchSurface() {
        let empty = ScrollPosition(idType: String.self)
        XCTAssertEqual(Mirror(reflecting: empty).children.map(\.label), ["storage", "idType", "seed"])
        XCTAssertNil(empty.viewID)
        XCTAssertNil(empty.edge)
        XCTAssertNil(empty.point)
        XCTAssertNil(empty.x)
        XCTAssertNil(empty.y)
        XCTAssertFalse(empty.isPositionedByUser)
        XCTAssertTrue(mirrorDigest(empty).contains("storage=automatic"))
        XCTAssertTrue(mirrorDigest(empty).contains("idType=String"))
        XCTAssertTrue(mirrorDigest(empty).contains("seed=0"))

        let id = ScrollPosition(id: "row-1", anchor: .center)
        XCTAssertEqual(id.viewID(type: String.self), "row-1")
        XCTAssertNil(id.viewID(type: Int.self))
        XCTAssertNil(id.edge)
        XCTAssertNil(id.point)
        XCTAssertTrue(mirrorDigest(id).contains("storage=viewID"))

        let edge = ScrollPosition(idType: String.self, edge: .bottom)
        XCTAssertEqual(edge.edge, .bottom)
        XCTAssertNil(edge.viewID)
        XCTAssertNil(edge.point)
        XCTAssertTrue(mirrorDigest(edge).contains("storage=edge"))

        let point = ScrollPosition(idType: String.self, point: CGPoint(x: 12.5, y: 34.75))
        XCTAssertEqual(point.point, CGPoint(x: 12.5, y: 34.75))
        XCTAssertNil(point.x)
        XCTAssertNil(point.y)
        XCTAssertTrue(mirrorDigest(point).contains("storage=point"))

        let xy = ScrollPosition(idType: String.self, x: 5, y: 6)
        XCTAssertEqual(xy.point, CGPoint(x: 5, y: 6))
        XCTAssertNil(xy.x)
        XCTAssertNil(xy.y)
        XCTAssertTrue(mirrorDigest(xy).contains("storage=point"))

        let xOnly = ScrollPosition(idType: String.self, x: 7)
        XCTAssertNil(xOnly.point)
        XCTAssertEqual(xOnly.x, 7)
        XCTAssertNil(xOnly.y)
        XCTAssertTrue(mirrorDigest(xOnly).contains("storage=x"))

        let yOnly = ScrollPosition(idType: String.self, y: 8)
        XCTAssertNil(yOnly.point)
        XCTAssertNil(yOnly.x)
        XCTAssertEqual(yOnly.y, 8)
        XCTAssertTrue(mirrorDigest(yOnly).contains("storage=y"))
    }

    func testPositionedByUserSetterIsOneWayAndClearsTarget() {
        var position = ScrollPosition(id: "row-1", anchor: .center)

        position.isPositionedByUser = true
        XCTAssertTrue(position.isPositionedByUser)
        XCTAssertNil(position.viewID)
        XCTAssertTrue(mirrorDigest(position).contains("storage=positionedByUser"))

        position.isPositionedByUser = false
        XCTAssertTrue(position.isPositionedByUser)
        XCTAssertNil(position.viewID)
        XCTAssertTrue(mirrorDigest(position).contains("storage=positionedByUser"))
        XCTAssertTrue(mirrorDigest(position).contains("seed=0"))
    }

    func testScrollToMutationsIncrementSeedAndReplaceStorage() {
        var position = ScrollPosition(idType: String.self)

        position.scrollTo(id: "row-3", anchor: .bottom)
        XCTAssertEqual(position.viewID(type: String.self), "row-3")
        XCTAssertNil(position.edge)
        XCTAssertNil(position.point)
        XCTAssertTrue(mirrorDigest(position).contains("storage=viewID"))
        XCTAssertTrue(mirrorDigest(position).contains("seed=1"))

        position.scrollTo(edge: .top)
        XCTAssertEqual(position.edge, .top)
        XCTAssertNil(position.viewID)
        XCTAssertNil(position.point)
        XCTAssertTrue(mirrorDigest(position).contains("storage=edge"))
        XCTAssertTrue(mirrorDigest(position).contains("seed=2"))

        position.scrollTo(point: CGPoint(x: 3, y: 4))
        XCTAssertEqual(position.point, CGPoint(x: 3, y: 4))
        XCTAssertNil(position.edge)
        XCTAssertNil(position.viewID)
        XCTAssertTrue(mirrorDigest(position).contains("storage=point"))
        XCTAssertTrue(mirrorDigest(position).contains("seed=3"))

        position.scrollTo(x: 9, y: 10)
        XCTAssertEqual(position.point, CGPoint(x: 9, y: 10))
        XCTAssertNil(position.x)
        XCTAssertNil(position.y)
        XCTAssertTrue(mirrorDigest(position).contains("storage=point"))
        XCTAssertTrue(mirrorDigest(position).contains("seed=4"))

        position.scrollTo(x: 11)
        XCTAssertNil(position.point)
        XCTAssertEqual(position.x, 11)
        XCTAssertNil(position.y)
        XCTAssertTrue(mirrorDigest(position).contains("storage=x"))
        XCTAssertTrue(mirrorDigest(position).contains("seed=5"))

        position.scrollTo(y: 12)
        XCTAssertNil(position.point)
        XCTAssertNil(position.x)
        XCTAssertEqual(position.y, 12)
        XCTAssertTrue(mirrorDigest(position).contains("storage=y"))
        XCTAssertTrue(mirrorDigest(position).contains("seed=6"))
    }

    func testEqualityIncludesAnchorIDTypeAndMutationSeed() {
        XCTAssertEqual(
            ScrollPosition(id: "row-1", anchor: .center),
            ScrollPosition(id: "row-1", anchor: .center)
        )
        XCTAssertNotEqual(
            ScrollPosition(id: "row-1", anchor: .center),
            ScrollPosition(id: "row-1", anchor: .top)
        )
        XCTAssertNotEqual(
            ScrollPosition(id: "row-1", anchor: .center),
            ScrollPosition(id: "row-2", anchor: .center)
        )
        XCTAssertNotEqual(
            ScrollPosition(idType: String.self),
            ScrollPosition(idType: Int.self)
        )

        let edgeInit = ScrollPosition(idType: String.self, edge: .top)
        var edgeMutated = ScrollPosition(idType: String.self)
        edgeMutated.scrollTo(edge: .top)
        XCTAssertNotEqual(edgeInit, edgeMutated)

        var secondMutation = edgeMutated
        secondMutation.scrollTo(edge: .top)
        XCTAssertNotEqual(edgeMutated, secondMutation)
    }
}
