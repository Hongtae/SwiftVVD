import Foundation
import XCTest
@testable import VUI

// ASSERTIONS textAllowsTightening27Observed

final class TextAllowsTighteningOwnerTests: XCTestCase {
    func testViewModifierPublishesNearestEnvironmentValue() throws {
        XCTAssertFalse(try resolvedValue { $0 })
        XCTAssertTrue(try resolvedValue { $0.allowsTightening(true) })
        XCTAssertFalse(try resolvedValue { $0.allowsTightening(false) })
        XCTAssertTrue(
            try resolvedValue {
                $0.allowsTightening(true).allowsTightening(false)
            }
        )
        XCTAssertFalse(
            try resolvedValue {
                $0.allowsTightening(false).allowsTightening(true)
            }
        )
    }

    func testParagraphContextPublishesTheEnvironmentValue() {
        var environment = EnvironmentValues()
        let disabled = makeParagraphStyle(
            context: ParagraphStyleResolutionContext(environment),
            alignment: nil,
            fallbackAlignment: .layoutBased,
            writingDirection: nil,
            fallbackWritingDirection: .contentBased,
            lineHeight: nil
        )
        XCTAssertFalse(disabled.allowsTightening)

        environment.allowsTightening = true
        let enabled = makeParagraphStyle(
            context: ParagraphStyleResolutionContext(environment),
            alignment: nil,
            fallbackAlignment: .layoutBased,
            writingDirection: nil,
            fallbackWritingDirection: .contentBased,
            lineHeight: nil
        )
        XCTAssertTrue(enabled.allowsTightening)
    }

    private func resolvedValue<Content: View>(
        transform: (TextAllowsTighteningProbe) -> Content
    ) throws -> Bool {
        let recorder = TextAllowsTighteningRecorder()
        let content = transform(
            TextAllowsTighteningProbe(recorder: recorder)
        )
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let source = graph.makeInput(value: content)
            _ = Content._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )
        }

        return try XCTUnwrap(recorder.value)
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

private final class TextAllowsTighteningRecorder {
    var value: Bool?
}

private struct TextAllowsTighteningProbe: View, TestPrimitiveView {
    typealias Body = Never

    let recorder: TextAllowsTighteningRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TextAllowsTighteningProbe._makeView requires an active graph."
            )
        }
        let value = view._attribute.value
        value.recorder.value = inputs.base.cachedEnvironment.value
            .environment.value.allowsTightening
        let layout = graph.makeInput(value: LayoutComputer.fixed(.zero))
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}
