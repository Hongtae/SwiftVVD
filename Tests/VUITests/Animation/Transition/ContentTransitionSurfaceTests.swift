import XCTest
@testable import VUI

private final class ContentTransitionEnvironmentRecorder {
    var environment: Attribute<EnvironmentValues>?
}

private struct ContentTransitionEnvironmentContent: View, TestPrimitiveView {
    var recorder: ContentTransitionEnvironmentRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let current = view._attribute.value
        current.recorder.environment = inputs.base.cachedEnvironment.value.environment
        return _ViewOutputs()
    }
}

final class ContentTransitionSurfaceTests: XCTestCase {
    func testContentTransitionFactoriesAndEquality() {
        XCTAssertEqual(ContentTransition.identity, .identity)
        XCTAssertEqual(ContentTransition.opacity, .opacity)
        XCTAssertEqual(ContentTransition.interpolate, .interpolate)
        XCTAssertNotEqual(ContentTransition.identity, .opacity)
        XCTAssertNotEqual(ContentTransition.opacity, .interpolate)

        XCTAssertEqual(ContentTransition.numericText(), .numericText(countsDown: false))
        XCTAssertNotEqual(ContentTransition.numericText(), .numericText(countsDown: true))
        XCTAssertEqual(ContentTransition.numericText(value: 12), .numericText(value: 12))
        XCTAssertEqual(ContentTransition.numericText(value: 12.5), .numericText(value: 12.5000001))
        XCTAssertNotEqual(ContentTransition.numericText(value: 12), .numericText(value: 13))
        XCTAssertNotEqual(ContentTransition.numericText(value: 12.5), .numericText(value: 12.500001))
        XCTAssertNotEqual(ContentTransition.numericText(value: .nan), .numericText(value: .nan))
        XCTAssertNotEqual(ContentTransition.numericText(), .numericText(value: 0))
    }

    func testContentTransitionEnvironmentDefaultsAndWrites() {
        var values = EnvironmentValues()

        XCTAssertNotEqual(values.contentTransition, .identity)
        XCTAssertNotEqual(values.contentTransition, .opacity)
        XCTAssertNotEqual(values.contentTransition, .interpolate)
        XCTAssertNotEqual(values.contentTransition, .numericText())
        XCTAssertFalse(values.contentTransitionAddsDrawingGroup)

        values.contentTransition = .numericText(countsDown: true)
        values.contentTransitionAddsDrawingGroup = true

        XCTAssertEqual(values.contentTransition, .numericText(countsDown: true))
        XCTAssertTrue(values.contentTransitionAddsDrawingGroup)
    }

    func testContentTransitionEnvironmentWritePreservesHiddenState() {
        let animation = Animation.linear(duration: 0.75)
        var values = EnvironmentValues()
        values.contentTransitionState = ContentTransition.State(
            transition: .opacity,
            style: .animatedWidget,
            animation: animation,
            options: [.formsGroup]
        )

        values.contentTransition = .symbolEffect(.replace.upUp)

        XCTAssertEqual(
            values.contentTransitionState.transition,
            .symbolEffect(.replace.upUp)
        )
        XCTAssertEqual(values.contentTransitionState.style, .animatedWidget)
        XCTAssertEqual(values.contentTransitionState.animation, animation)
        XCTAssertEqual(values.contentTransitionState.options, [.formsGroup])

        // ASSERTIONS contentTransitionStateEnvironmentStorageObserved
    }

    func testContentTransitionModifierPublishesEnvironmentValue() throws {
        let graph = _AGGraph()
        let recorder = ContentTransitionEnvironmentRecorder()

        try _AGGraph.withCurrent(graph) {
            let view = ContentTransitionEnvironmentContent(recorder: recorder)
                .contentTransition(.opacity)
            let viewAttr = graph.makeInput(value: view)

            _ = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: makeViewInputs(graph: graph)
            )

            let environment = try XCTUnwrap(recorder.environment)
            XCTAssertEqual(environment.value.contentTransition, .opacity)
            XCTAssertFalse(environment.value.contentTransitionAddsDrawingGroup)
        }
    }

    func testContentTransitionDrawingGroupEnvironmentWrites() throws {
        let graph = _AGGraph()
        let recorder = ContentTransitionEnvironmentRecorder()

        try _AGGraph.withCurrent(graph) {
            let view = ContentTransitionEnvironmentContent(recorder: recorder)
                .environment(\.contentTransitionAddsDrawingGroup, true)
                .contentTransition(.interpolate)
            let viewAttr = graph.makeInput(value: view)

            _ = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: makeViewInputs(graph: graph)
            )

            let environment = try XCTUnwrap(recorder.environment)
            XCTAssertEqual(environment.value.contentTransition, .interpolate)
            XCTAssertTrue(environment.value.contentTransitionAddsDrawingGroup)
        }
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: Phase()),
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
