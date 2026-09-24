import Foundation
import XCTest
@testable import VUI

// ASSERTIONS scaledMetric27Observed

final class ScaledMetricDynamicPropertyTests: XCTestCase {
    private func mountedValue(
        displayScale: CGFloat,
        defaultPixelLength: CGFloat? = nil,
        dynamicTypeSize: DynamicTypeSize = .large
    ) -> Double {
        let graph = _AGGraph()
        return _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues()
            environment.displayScale = displayScale
            environment.defaultPixelLength = defaultPixelLength
            environment.dynamicTypeSize = dynamicTypeSize
            var metric = ScaledMetric<Double>(
                wrappedValue: 10.26,
                relativeTo: .body
            )
            var inputs = _GraphInputs(
                time: graph.makeInput(value: Time.zero),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: environment),
                transaction: graph.makeInput(value: Transaction())
            )
            let buffer = _DynamicPropertyBuffer(
                fields: .init(
                    entries: [.init(offset: 0, type: ScaledMetric<Double>.self)]
                ),
                container: _GraphValue(
                    _attribute: graph.makeInput(value: metric)
                ),
                inputs: &inputs
            )
            buffer.applyContexts(to: &metric)
            return metric.wrappedValue
        }
    }

    func testMountedMetricReadsPixelLengthEnvironment() {
        XCTAssertEqual(mountedValue(displayScale: 0), 10)
        XCTAssertEqual(mountedValue(displayScale: 1), 10)
        XCTAssertEqual(mountedValue(displayScale: 2), 10.5)
        XCTAssertEqual(mountedValue(displayScale: 3), 31 / 3, accuracy: 0.000_001)
        XCTAssertEqual(mountedValue(displayScale: 4), 10.25)
        XCTAssertEqual(
            mountedValue(displayScale: 2, defaultPixelLength: 0.25),
            10.25
        )
    }

    func testCurrentMacOSScaleFactorIsOneForEveryDynamicTypeSize() {
        for dynamicTypeSize in DynamicTypeSize.allCases {
            for textStyle in Font.TextStyle.allCases {
                XCTAssertEqual(
                    Font.scaleFactor(
                        textStyle: textStyle,
                        in: dynamicTypeSize
                    ),
                    1
                )
            }
            XCTAssertEqual(
                mountedValue(
                    displayScale: 1,
                    dynamicTypeSize: dynamicTypeSize
                ),
                10
            )
        }
    }
}
