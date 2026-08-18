import XCTest
@testable import VUI

final class AGThreadLocalTests: XCTestCase {
    func testNestedBindingRestoresOuterValueAndDefault() {
        let local = _AGThreadLocal(7)

        XCTAssertEqual(local.value, 7)
        local.withValue(11) {
            XCTAssertEqual(local.value, 11)
            local.withValue(23) {
                XCTAssertEqual(local.value, 23)
            }
            XCTAssertEqual(local.value, 11)
        }
        XCTAssertEqual(local.value, 7)
    }

    func testNilOptionalBindingShadowsNonNilDefault() {
        let local = _AGThreadLocal<Int?>(5)

        local.withValue(nil) {
            XCTAssertNil(local.value)
        }
        XCTAssertEqual(local.value, 5)
    }

    func testThrowingBindingRestoresPreviousValue() {
        let local = _AGThreadLocal("default")

        XCTAssertThrowsError(
            try local.withValue("bound") {
                XCTAssertEqual(local.value, "bound")
                throw AGThreadLocalTestError.expected
            }
        )
        XCTAssertEqual(local.value, "default")
    }
}

private enum AGThreadLocalTestError: Error {
    case expected
}
