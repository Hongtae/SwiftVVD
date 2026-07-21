import XCTest
@testable import VUI

final class AffineTransformTests: XCTestCase {
    func testIdentityTransformPreservesNonSquareRectangleBounds() {
        let rect = CGRect(x: 2, y: 10, width: 3, height: 7)

        let transformed = rect.applying(VUI.AffineTransform.identity)

        XCTAssertEqual(transformed, rect)
    }
}
