import XCTest
@testable import VUI

private struct KeyframeSizedView: View, TestPrimitiveView {
    var value: Double

    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(
                CGSize(width: view._attribute.value.value, height: 17)
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct KeyframeAnimatorRelaySource: View, TestPrimitiveView {
    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 31, height: 23))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

final class KeyframeAnimatorTests: XCTestCase {
    // ASSERTIONS keyframeAnimatorFieldMetadataObserved
    func testStorageLabelsAndPlaybackCarrierMatchObservedShape() {
        let repeating = makeRepeatingAnimator(repeating: false)
        XCTAssertEqual(Mirror(reflecting: repeating).children.map(\.label), [
            "initialValue",
            "path",
            "playback",
            "content",
        ])

        let repeatingPlayback = try! XCTUnwrap(
            Mirror(reflecting: repeating).children.first { $0.label == "playback" }
        ).value
        XCTAssertEqual(
            Mirror(reflecting: repeatingPlayback).children.first?.label,
            "repeating"
        )

        let triggered = makeTriggeredAnimator(trigger: 7)
        let triggeredPlayback = try! XCTUnwrap(
            Mirror(reflecting: triggered).children.first { $0.label == "playback" }
        ).value
        XCTAssertEqual(
            Mirror(reflecting: triggeredPlayback).children.first?.label,
            "onChange"
        )
    }

    // ASSERTIONS keyframeAnimatorPlaybackRuntimeObserved
    func testRepeatingPlaybackPausesAndResumesFromPresentationTime() throws {
        try withKeyframeAnimatorHost { viewGraph, graph in
            typealias Animator = KeyframeAnimator<
                Double,
                KeyframeTrack<Double, Double, LinearKeyframe<Double>>,
                KeyframeSizedView
            >

            let source: Attribute<Animator> = graph.makeInput(
                value: makeRepeatingAnimator(repeating: true)
            )
            let (inputs, time, phase) = makeViewInputs(graph: graph)
            let outputs = Animator._makeView(
                view: _GraphValue(_attribute: source),
                inputs: inputs
            )

            func sample(_ seconds: Double) throws -> Double {
                time.setValue(Time(seconds: seconds))
                let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
                return layout.sizeThatFits(.unspecified).width
            }

            XCTAssertEqual(try sample(0), 0, accuracy: 0.000_001)
            XCTAssertEqual(
                viewGraph.nextUpdate.views.time.seconds,
                1.0 / 120.0,
                accuracy: 0.000_001
            )
            XCTAssertEqual(try sample(0.1), 0, accuracy: 0.000_001)
            XCTAssertEqual(try sample(0.6), 5, accuracy: 0.000_001)

            source.setValue(makeRepeatingAnimator(repeating: false))
            XCTAssertEqual(try sample(0.6), 5, accuracy: 0.000_001)
            viewGraph.nextUpdate.views = ViewGraph.NextUpdate()
            XCTAssertEqual(try sample(1.0), 5, accuracy: 0.000_001)
            XCTAssertTrue(viewGraph.nextUpdate.views.time.seconds.isInfinite)

            source.setValue(makeRepeatingAnimator(repeating: true))
            XCTAssertEqual(try sample(1.0), 5, accuracy: 0.000_001)
            XCTAssertEqual(try sample(1.2), 5, accuracy: 0.000_001)
            XCTAssertEqual(try sample(1.4), 7, accuracy: 0.000_001)

            var resetPhase = Phase()
            resetPhase.resetSeed = 1
            phase.setValue(resetPhase)
            XCTAssertEqual(try sample(1.4), 0, accuracy: 0.000_001)
        }
    }

    // ASSERTIONS keyframeAnimatorRetargetAndPauseDisassemblyObserved
    func testTriggerRetargetUsesCurrentPresentationValue() throws {
        try withKeyframeAnimatorHost { _, graph in
            typealias Animator = KeyframeAnimator<
                Double,
                KeyframeTrack<Double, Double, LinearKeyframe<Double>>,
                KeyframeSizedView
            >

            var planInitialValues: [Double] = []
            func makeAnimator(trigger: Int) -> Animator {
                Animator(
                    initialValue: 0,
                    trigger: trigger,
                    content: { KeyframeSizedView(value: $0) },
                    keyframes: { value in
                        planInitialValues.append(value)
                        return KeyframeTrack(\.self) {
                            LinearKeyframe(value + 10, duration: 1)
                        }
                    }
                )
            }

            let source = graph.makeInput(value: makeAnimator(trigger: 0))
            let (inputs, time, _) = makeViewInputs(graph: graph)
            let outputs = Animator._makeView(
                view: _GraphValue(_attribute: source),
                inputs: inputs
            )

            func sample(_ seconds: Double) throws -> Double {
                time.setValue(Time(seconds: seconds))
                let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
                return layout.sizeThatFits(.unspecified).width
            }

            XCTAssertEqual(try sample(0), 0, accuracy: 0.000_001)
            XCTAssertTrue(planInitialValues.isEmpty)

            source.setValue(makeAnimator(trigger: 1))
            XCTAssertEqual(try sample(0), 0, accuracy: 0.000_001)
            XCTAssertEqual(planInitialValues, [0])
            XCTAssertEqual(try sample(0.1), 0, accuracy: 0.000_001)
            XCTAssertEqual(try sample(0.5), 4, accuracy: 0.000_001)

            source.setValue(makeAnimator(trigger: 2))
            XCTAssertEqual(try sample(0.5), 4, accuracy: 0.000_001)
            XCTAssertEqual(planInitialValues, [0, 4])
            XCTAssertEqual(try sample(0.6), 4, accuracy: 0.000_001)
            XCTAssertEqual(try sample(0.8), 6, accuracy: 0.000_001)
            XCTAssertEqual(try sample(1.7), 14, accuracy: 0.000_001)

            source.setValue(makeAnimator(trigger: 3))
            XCTAssertEqual(try sample(1.7), 0, accuracy: 0.000_001)
            XCTAssertEqual(planInitialValues, [0, 4, 0])
        }
    }

    func testViewModifierRelaysPlaceholderContent() throws {
        try withKeyframeAnimatorHost { _, graph in
            let view = KeyframeAnimatorRelaySource().keyframeAnimator(
                initialValue: 0.0,
                repeating: false,
                content: { placeholder, _ in placeholder },
                keyframes: { _ in
                    LinearKeyframe(1.0, duration: 1)
                }
            )
            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph).inputs
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(
                layout.sizeThatFits(.unspecified),
                CGSize(width: 31, height: 23)
            )
        }
    }

    private func makeRepeatingAnimator(
        repeating: Bool
    ) -> KeyframeAnimator<
        Double,
        KeyframeTrack<Double, Double, LinearKeyframe<Double>>,
        KeyframeSizedView
    > {
        KeyframeAnimator(
            initialValue: 0,
            repeating: repeating,
            content: { KeyframeSizedView(value: $0) },
            keyframes: { _ in
                KeyframeTrack(\.self) {
                    LinearKeyframe(10.0, duration: 1)
                }
            }
        )
    }

    private func makeTriggeredAnimator(
        trigger: Int
    ) -> KeyframeAnimator<
        Double,
        KeyframeTrack<Double, Double, LinearKeyframe<Double>>,
        KeyframeSizedView
    > {
        KeyframeAnimator(
            initialValue: 0,
            trigger: trigger,
            content: { KeyframeSizedView(value: $0) },
            keyframes: { _ in
                KeyframeTrack(\.self) {
                    LinearKeyframe(10.0, duration: 1)
                }
            }
        )
    }

    private func makeViewInputs(
        graph: _AGGraph
    ) -> (
        inputs: _ViewInputs,
        time: Attribute<Time>,
        phase: Attribute<Phase>
    ) {
        let environment = graph.makeInput(value: EnvironmentValues())
        let time = graph.makeInput(value: Time(seconds: 0))
        let phase = graph.makeInput(value: Phase())
        let base = _GraphInputs(
            time: time,
            phase: phase,
            environment: environment,
            transaction: graph.makeInput(value: Transaction())
        )
        return (
            _ViewInputs(
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
            ),
            time,
            phase
        )
    }

    private func withKeyframeAnimatorHost(
        _ body: (ViewGraph, _AGGraph) throws -> Void
    ) rethrows {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        try viewGraph.data.withCurrent {
            try body(viewGraph, viewGraph.data.graph)
        }
    }
}
