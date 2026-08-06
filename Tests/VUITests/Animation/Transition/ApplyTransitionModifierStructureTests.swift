import Observation
import XCTest
@testable import VUI

@Observable
private final class TransitionApplicationState {
    var token = 0
}

private final class TransitionApplicationRecorder {
    var bodyTypeName = ""
    var bodyEvaluations = 0
    var relayedContentCalls = 0
    var observedToken = -1
    var observedPhase: TransitionPhase?
    var child: Attribute<TransitionApplicationBody>?
}

private struct TransitionApplicationProbe: Transition {
    var state: TransitionApplicationState
    var recorder: TransitionApplicationRecorder

    func body(
        content: PlaceholderContentView<Self>,
        phase: TransitionPhase
    ) -> TransitionApplicationBody {
        recorder.bodyEvaluations += 1
        recorder.observedToken = state.token
        recorder.observedPhase = phase
        return TransitionApplicationBody(
            content: content,
            recorder: recorder
        )
    }
}

private struct TransitionApplicationBody: View, TestPrimitiveView {
    var content: PlaceholderContentView<TransitionApplicationProbe>
    var recorder: TransitionApplicationRecorder

    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        let bodyTypeName = String(
            reflecting: view._attribute.identifier._bodyType
        )
        let resolved = view._attribute.value
        resolved.recorder.bodyTypeName = bodyTypeName
        resolved.recorder.child = view._attribute
        return PlaceholderContentView<TransitionApplicationProbe>._makeView(
            view: view[\.content],
            inputs: inputs
        )
    }
}

final class ApplyTransitionModifierStructureTests: XCTestCase {
    func testApplyTransitionModifierUsesPrimitiveMultiViewChildRuleRoute() throws {
        func requirePrimitive<M: PrimitiveViewModifier>(_: M.Type) {}
        func requireMulti<M: MultiViewModifier>(_: M.Type) {}

        typealias Modifier = ApplyTransitionModifier<TransitionApplicationProbe>
        requirePrimitive(Modifier.self)
        requireMulti(Modifier.self)
        XCTAssertTrue(Modifier.Body.self == Never.self)

        let graph = _AGGraph()
        let recorder = TransitionApplicationRecorder()
        let state = TransitionApplicationState()

        try _AGGraph.withCurrent(graph) {
            let modifier = Modifier(
                transition: TransitionApplicationProbe(
                    state: state,
                    recorder: recorder
                ),
                phase: .didDisappear
            )
            let modifierAttribute = graph.makeInput(value: modifier)

            _ = Modifier._makeView(
                modifier: _GraphValue(_attribute: modifierAttribute),
                inputs: makeViewInputs(graph: graph)
            ) { _, _ in
                recorder.relayedContentCalls += 1
                return _ViewOutputs()
            }

            XCTAssertTrue(
                recorder.bodyTypeName.contains("ApplyTransitionModifier")
            )
            XCTAssertTrue(recorder.bodyTypeName.contains(".Child"))
            XCTAssertEqual(recorder.bodyEvaluations, 1)
            XCTAssertEqual(recorder.relayedContentCalls, 1)
            XCTAssertEqual(recorder.observedToken, 0)
            XCTAssertEqual(recorder.observedPhase, .didDisappear)

            state.token = 1
            XCTAssertTrue(graph.inbox.hasPendingWork)
            graph.inbox.drain()

            let child = try XCTUnwrap(recorder.child)
            _ = child.value
            XCTAssertEqual(recorder.bodyEvaluations, 2)
            XCTAssertEqual(recorder.observedToken, 1)

            XCTAssertEqual(
                Modifier._viewListCount(
                    inputs: _ViewListCountInputs(
                        base: makeGraphInputs(graph: graph)
                    ),
                    body: { _ in 12 }
                ),
                1
            )
        }
    }

    private func makeGraphInputs(graph: _AGGraph) -> _GraphInputs {
        _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: Transaction())
        )
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        _ViewInputs(
            base: makeGraphInputs(graph: graph),
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
