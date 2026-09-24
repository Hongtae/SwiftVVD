import Foundation
import XCTest
import VUI

// ASSERTIONS scaledMetric27Observed

private struct PublicScaledMetricProbe {
    @ScaledMetric var implicit = 10.26
    @ScaledMetric(relativeTo: .caption) var explicit = 10.26
    @ScaledMetric var float: Float = 10.26
}

final class ScaledMetricTests: XCTestCase {
    private func requireDynamicProperty<Value: DynamicProperty>(
        _: Value.Type
    ) {}

    private func requireSendable<Value: Sendable>(_: Value.Type) {}

    func testPublicSurfaceAndStorageMatchNativeProbe() {
        requireDynamicProperty(ScaledMetric<Double>.self)
        requireSendable(ScaledMetric<Double>.self)

        let implicit = ScaledMetric<Double>(wrappedValue: 10.13)
        let explicit = ScaledMetric<Double>(
            wrappedValue: 10.13,
            relativeTo: .caption
        )
        XCTAssertEqual(
            Mirror(reflecting: implicit).children.map(\.label),
            ["_dynamicTypeSize", "_pixelLength", "value", "textStyle"]
        )
        XCTAssertEqual(
            Mirror(reflecting: explicit).children.map(\.label),
            ["_dynamicTypeSize", "_pixelLength", "value", "textStyle"]
        )
    }

    func testOutsideViewUsesDefaultEnvironmentAndPixelRounding() {
        XCTAssertEqual(
            [10.13, 10.26, 10.5, -10.26, -10.5, 0].map {
                ScaledMetric<Double>(wrappedValue: $0).wrappedValue
            },
            [10, 10, 11, -10, -11, 0]
        )

        let values = PublicScaledMetricProbe()
        XCTAssertEqual(values.implicit, 10)
        XCTAssertEqual(values.explicit, 10)
        XCTAssertEqual(values.float, 10)
    }

    func testPixelLengthTracksDisplayScale() {
        var environment = EnvironmentValues()
        XCTAssertEqual(environment.pixelLength, 1)
        environment.displayScale = 2
        XCTAssertEqual(environment.pixelLength, 0.5)
        environment.displayScale = 3
        XCTAssertEqual(environment.pixelLength, 1 / 3, accuracy: 0.000_001)
        environment.displayScale = 4
        XCTAssertEqual(environment.pixelLength, 0.25)
    }
}
