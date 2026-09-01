#if os(macOS)
import XCTest
@testable import VVD

final class AppKitScreenCoordinateTests: XCTestCase {
    func testNativeVisibleFrameConvertsToTopLeftExternalCoordinates() {
        let nativeFrame = CGRect(x: 0, y: 51, width: 1728, height: 1033)
        let converted = AppKitScreen.topLeftRect(
            fromNative: nativeFrame,
            referenceY: 1117
        )

        XCTAssertEqual(converted, CGRect(x: 0, y: 33, width: 1728, height: 1033))
    }

    func testNativeRectConversionPreservesGlobalDisplayOffsets() {
        let nativeFrame = CGRect(x: 1728, y: -900, width: 1440, height: 900)
        let converted = AppKitScreen.topLeftRect(
            fromNative: nativeFrame,
            referenceY: 1117
        )

        XCTAssertEqual(converted, CGRect(x: 1728, y: 1117, width: 1440, height: 900))
    }

    func testScreenPointConversionRoundTripsAcrossCoordinateOrigins() {
        let nativePoint = CGPoint(x: 207, y: 774)
        let topLeftPoint = AppKitScreen.topLeftPoint(
            fromNative: nativePoint,
            referenceY: 1117
        )
        let roundTrip = AppKitScreen.nativePoint(
            fromTopLeft: topLeftPoint,
            referenceY: 1117
        )

        XCTAssertEqual(topLeftPoint, CGPoint(x: 207, y: 343))
        XCTAssertEqual(roundTrip, nativePoint)
    }
}
#endif
