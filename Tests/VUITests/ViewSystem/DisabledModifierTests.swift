import XCTest
@testable import VUI

final class DisabledModifierTests: XCTestCase {
    // ASSERTIONS viewDisabledEnvironmentCompositionObserved
    func testDisabledTransformsInheritedIsEnabledWithoutReenabling() throws {
        XCTAssertTrue(try resolvedIsEnabled { $0.disabled(false) })
        XCTAssertFalse(try resolvedIsEnabled { $0.disabled(true) })

        XCTAssertFalse(
            try resolvedIsEnabled {
                $0.disabled(false).disabled(true)
            }
        )
        XCTAssertFalse(
            try resolvedIsEnabled {
                $0.disabled(true).disabled(false)
            }
        )
        XCTAssertFalse(
            try resolvedIsEnabled(parentIsEnabled: false) {
                $0.disabled(false)
            }
        )
    }

    private func resolvedIsEnabled<Content: View>(
        parentIsEnabled: Bool = true,
        transform: (DisabledEnvironmentProbe) -> Content
    ) throws -> Bool {
        let recorder = DisabledEnvironmentRecorder()
        let content = transform(DisabledEnvironmentProbe(recorder: recorder))
        let graph = _AGGraph()
        let graphContext = _AGGraphContext(graph: graph)

        graphContext.withCurrent {
            var environment = EnvironmentValues()
            environment.isEnabled = parentIsEnabled
            let source = graph.makeInput(value: content)
            _ = Content._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(
                    graph: graph,
                    environment: graph.makeInput(value: environment)
                )
            )
        }

        return try XCTUnwrap(recorder.isEnabled)
    }

    private func makeViewInputs(
        graph: _AGGraph,
        environment: Attribute<EnvironmentValues>
    ) -> _ViewInputs {
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: environment,
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
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}

private final class DisabledEnvironmentRecorder {
    var isEnabled: Bool?
}

private struct DisabledEnvironmentProbe: View, TestPrimitiveView {
    typealias Body = Never

    let recorder: DisabledEnvironmentRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "DisabledEnvironmentProbe._makeView called outside an active graph."
            )
        }
        let value = view._attribute.value
        value.recorder.isEnabled =
            inputs.base.cachedEnvironment.value.environment.value.isEnabled
        let layout = graph.makeInput(value: LayoutComputer.fixed(.zero))
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}
