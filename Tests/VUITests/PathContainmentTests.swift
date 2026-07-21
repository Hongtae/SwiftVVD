import XCTest
@testable import VUI

final class PathContainmentTests: XCTestCase {
    func testRoundedRectangleRejectsPointsOutsideItsBoundingRect() {
        let path = Path(
            roundedRect: CGRect(x: 0, y: 0, width: 8, height: 8),
            cornerRadius: 4
        )

        XCTAssertTrue(path.contains(CGPoint(x: 4, y: 4)))
        XCTAssertFalse(path.contains(CGPoint(x: 161, y: 4)))
        XCTAssertFalse(path.contains(CGPoint(x: -1, y: 4)))
    }
}
