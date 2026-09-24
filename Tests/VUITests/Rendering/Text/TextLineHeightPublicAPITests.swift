import Foundation
import XCTest
import VUI

// ASSERTIONS textLineHeightPublic27Observed

final class TextLineHeightPublicAPITests: XCTestCase {
    private func requireView<V: View>(_ value: V) {
        _ = value
    }

    private func requireConformances<T: Codable & Hashable & Sendable>(
        _: T.Type
    ) {}

    func testPublicEnvironmentValueAndViewProducerAreAvailable() {
        requireConformances(AttributedString.LineHeight.self)
        XCTAssertEqual(AttributedString.LineHeight.normal, .multiple(factor: 1.2))
        XCTAssertEqual(AttributedString.LineHeight.tight, .multiple(factor: 1))
        XCTAssertEqual(AttributedString.LineHeight.loose, .multiple(factor: 1.5))
        XCTAssertNotEqual(AttributedString.LineHeight.variable, .normal)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let values: [(AttributedString.LineHeight, String)] = [
            (.variable, #"{"baselineInterval":{"variable":{}}}"#),
            (.normal, #"{"baselineInterval":{"multiple":{"factor":1.2}}}"#),
            (.tight, #"{"baselineInterval":{"multiple":{"factor":1}}}"#),
            (.loose, #"{"baselineInterval":{"multiple":{"factor":1.5}}}"#),
            (.multiple(factor: 2), #"{"baselineInterval":{"multiple":{"factor":2}}}"#),
            (.leading(increase: -7), #"{"baselineInterval":{"leading":{"increase":-7}}}"#),
            (.exact(points: 40), #"{"baselineInterval":{"exact":{"points":40}}}"#),
        ]
        for (value, expected) in values {
            let data = try! encoder.encode(value)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), expected)
            XCTAssertEqual(
                try! JSONDecoder().decode(
                    AttributedString.LineHeight.self,
                    from: data
                ),
                value
            )
        }

        var environment = EnvironmentValues()
        XCTAssertNil(environment.lineHeight)
        environment.lineHeight = .exact(points: 40)
        XCTAssertEqual(environment.lineHeight, .exact(points: 40))

        var copy = environment
        copy.lineHeight = .multiple(factor: 2)
        XCTAssertEqual(environment.lineHeight, .exact(points: 40))
        XCTAssertEqual(copy.lineHeight, .multiple(factor: 2))
        copy.lineHeight = nil
        XCTAssertNil(copy.lineHeight)

        requireView(EmptyView().lineHeight(nil))
        requireView(EmptyView().lineHeight(.exact(points: 40)))
        requireView(
            EmptyView().lineHeight(.exact(points: 40))
                .lineHeight(.multiple(factor: 2))
        )
        requireView(
            EmptyView().lineHeight(.multiple(factor: 2))
                .lineHeight(.exact(points: 40))
        )
    }
}
