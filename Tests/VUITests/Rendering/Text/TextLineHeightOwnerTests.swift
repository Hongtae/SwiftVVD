import CoreText
import Foundation
import XCTest
@testable import VUI

// ASSERTIONS textLineHeightPublic27Observed
// ASSERTIONS textLineHeightCoreTextConversion27Observed
// ASSERTIONS textLineHeightCodableExtraction27Observed

final class TextLineHeightOwnerTests: XCTestCase {
    func testIntervalConversionPreservesKindAndScalarBits() {
        let cases: [(AttributedString.LineHeight, Int, UInt64)] = [
            (.variable, 0, 0x0000_0000_0000_0000),
            (.multiple(factor: -0.0), 1, 0x8000_0000_0000_0000),
            (
                .multiple(
                    factor: CGFloat(
                        Double(bitPattern: 0x7ff8_0000_0000_1234)
                    )
                ),
                1,
                0x7ff8_0000_0000_1234
            ),
            (.leading(increase: .infinity), 2, 0x7ff0_0000_0000_0000),
            (.exact(points: -.infinity), 3, 0xfff0_0000_0000_0000),
        ]

        for (lineHeight, expectedKind, expectedBits) in cases {
            let actual: (kind: Int, bits: UInt64)
            switch lineHeight.textLineHeightInterval {
            case .variable:
                actual = (0, 0)
            case let .multiple(value):
                actual = (1, UInt64(value.bitPattern))
            case let .leading(value):
                actual = (2, UInt64(value.bitPattern))
            case let .exact(value):
                actual = (3, UInt64(value.bitPattern))
            }
            XCTAssertEqual(actual.kind, expectedKind)
            XCTAssertEqual(actual.bits, expectedBits)
        }
    }

    func testViewModifierPublishesNearestEnvironmentValue() {
        XCTAssertNil(resolvedValue { $0 })
        XCTAssertEqual(
            resolvedValue { $0.lineHeight(.exact(points: 40)) },
            .exact(points: 40)
        )
        XCTAssertEqual(
            resolvedValue { $0.lineHeight(.multiple(factor: 2)) },
            .multiple(factor: 2)
        )
        XCTAssertEqual(
            resolvedValue {
                $0.lineHeight(.exact(points: 40))
                    .lineHeight(.multiple(factor: 2))
            },
            .exact(points: 40)
        )
        XCTAssertEqual(
            resolvedValue {
                $0.lineHeight(.multiple(factor: 2))
                    .lineHeight(.exact(points: 40))
            },
            .multiple(factor: 2)
        )
        XCTAssertEqual(
            resolvedValue {
                $0.lineHeight(.exact(points: 40)).lineHeight(nil)
            },
            .exact(points: 40)
        )
    }

    func testParagraphAndMetricsOwnersRetainThePublicValue() {
        var environment = EnvironmentValues()
        XCTAssertNil(ParagraphStyleResolutionContext(environment).lineHeight)

        environment.lineHeight = .exact(points: 40)
        let exact = makeParagraphStyle(
            context: ParagraphStyleResolutionContext(environment),
            alignment: nil,
            fallbackAlignment: .layoutBased,
            writingDirection: nil,
            fallbackWritingDirection: .contentBased,
            lineHeight: nil
        )
        XCTAssertEqual(exact.baselineInterval, .exact(points: 40))

        var properties = Text.ResolvedProperties()
        _ = properties.style(
            environment: environment,
            alignment: nil,
            writingDirection: nil,
            lineHeight: .multiple(factor: 2)
        )
        XCTAssertEqual(properties.lineHeightMetrics.multiple, 2)
        XCTAssertNil(properties.lineHeightMetrics.exact)

        var metrics = Text.ResolvedProperties.LineHeightMetrics()
        metrics.update(.normal)
        metrics.update(.leading(increase: -7))
        metrics.update(.exact(points: 40))
        XCTAssertEqual(metrics.multiple, 1.2)
        XCTAssertEqual(metrics.leading, -7)
        XCTAssertEqual(metrics.exact, 40)
    }

    private func resolvedValue<Content: View>(
        transform: (TextLineHeightProbe) -> Content
    ) -> AttributedString.LineHeight? {
        let recorder = TextLineHeightRecorder()
        let content = transform(TextLineHeightProbe(recorder: recorder))
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let source = graph.makeInput(value: content)
            _ = Content._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )
        }

        XCTAssertTrue(recorder.didRecord)
        return recorder.value
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: Transaction())
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: .zero),
            containerPosition: graph.makeInput(value: .zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}

private final class TextLineHeightRecorder {
    var didRecord = false
    var value: AttributedString.LineHeight?
}

private struct TextLineHeightProbe: View, TestPrimitiveView {
    typealias Body = Never

    let recorder: TextLineHeightRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("TextLineHeightProbe._makeView requires an active graph.")
        }
        let value = view._attribute.value
        value.recorder.didRecord = true
        value.recorder.value = inputs.base.cachedEnvironment.value
            .environment.value.lineHeight
        let layout = graph.makeInput(value: LayoutComputer.fixed(.zero))
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}
