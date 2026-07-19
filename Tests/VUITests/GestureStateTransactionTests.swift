import XCTest
@testable import VUI

final class GestureStateTransactionTests: XCTestCase {
    func testUpdatingThenOnEndedDrainsGestureStateResetBeforeEndedCallback() {
        let gestureGraph = GestureGraph()
        let graph = gestureGraph.data.graph

        gestureGraph.data.withCurrent {
            let phase = graph.makeInput(value: GesturePhase<Int>.possible(nil))
            var events: [String] = []
            let state = GestureState<Int>(wrappedValue: 0) { value, _ in
                events.append("reset:\(value)")
            }
            let gesture = ControlledGesture(phase: phase)
                .updating(state) { value, current, _ in
                    events.append("updating:\(value):\(current)")
                    current = value
                }
                .onEnded { value in
                    events.append("ended:\(value)")
                }
            let gestureAttr = graph.makeInput(value: gesture)

            let outputs = type(of: gesture)._makeGesture(
                gesture: _GraphValue(_attribute: gestureAttr),
                inputs: makeGestureInputs(graph: graph, usesGestureGraph: true)
            )

            phase.setValue(.active(4))
            _ = outputs.phase.value
            drainGestureGraphActions(gestureGraph)
            XCTAssertEqual(events, ["updating:4:0"])

            phase.setValue(.ended(4))
            _ = outputs.phase.value
            drainGestureGraphActions(gestureGraph)
            XCTAssertEqual(events, [
                "updating:4:0",
                "reset:4",
                "ended:4",
            ])
        }
    }

    func testUpdatingThenOnChangedDrainsThroughGestureActionQueue() {
        let gestureGraph = GestureGraph()
        let graph = gestureGraph.data.graph

        gestureGraph.data.withCurrent {
            let phase = graph.makeInput(value: GesturePhase<Int>.possible(nil))
            var events: [String] = []
            let state = GestureState<Int>(wrappedValue: 1)
            let gesture = ControlledGesture(phase: phase)
                .updating(state) { value, current, _ in
                    events.append("updating:\(value):\(current)")
                    current = value
                }
                .onChanged { value in
                    events.append("changed:\(value)")
                }
            let gestureAttr = graph.makeInput(value: gesture)

            let outputs = type(of: gesture)._makeGesture(
                gesture: _GraphValue(_attribute: gestureAttr),
                inputs: makeGestureInputs(graph: graph, usesGestureGraph: true)
            )

            phase.setValue(.active(6))
            _ = outputs.phase.value
            XCTAssertEqual(events, [])

            drainGestureGraphActions(gestureGraph)
            XCTAssertEqual(events, [
                "updating:6:1",
                "changed:6",
            ])
        }
    }

    func testActiveWritebackDoesNotReenterPhaseRuleForFallbackStorage() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let phase = graph.makeInput(value: GesturePhase<Int>.possible(nil))
            var bodyEvents: [GestureStateBodyEvent] = []
            var resetEvents: [GestureStateResetEvent] = []
            let state = GestureState<Int>(wrappedValue: 1) { value, transaction in
                resetEvents.append(.init(value: value, tracksVelocity: transaction.tracksVelocity))
            }
            let gesture = ControlledGesture(phase: phase)
                .updating(state) { value, current, transaction in
                    bodyEvents.append(.init(
                        value: value,
                        current: current,
                        tracksVelocity: transaction.tracksVelocity
                    ))
                    current += value
                }
            let gestureAttr = graph.makeInput(value: gesture)

            _ = type(of: gesture)._makeGesture(
                gesture: _GraphValue(_attribute: gestureAttr),
                inputs: makeGestureInputs(graph: graph)
            )

            Update.ensure {
                phase.setValue(.active(2))
                XCTAssertTrue(bodyEvents.isEmpty)
            }

            XCTAssertEqual(bodyEvents, [
                .init(value: 2, current: 1, tracksVelocity: true)
            ])

            Update.ensure {
                phase.setValue(.active(3))
            }

            XCTAssertEqual(bodyEvents, [
                .init(value: 2, current: 1, tracksVelocity: true),
                .init(value: 3, current: 3, tracksVelocity: true)
            ])

            Update.ensure {
                phase.setValue(.ended(0))
            }

            XCTAssertEqual(resetEvents, [
                .init(value: 6, tracksVelocity: true)
            ])

            Update.ensure {
                phase.setValue(.ended(9))
            }

            XCTAssertEqual(resetEvents, [
                .init(value: 6, tracksVelocity: true)
            ])

            Update.ensure {
                phase.setValue(.active(4))
            }

            XCTAssertEqual(bodyEvents, [
                .init(value: 2, current: 1, tracksVelocity: true),
                .init(value: 3, current: 3, tracksVelocity: true),
                .init(value: 4, current: 1, tracksVelocity: true)
            ])
        }
    }

    func testActiveAndResetWritebackCarryMutatedTransactionToLocation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let phase = graph.makeInput(value: GesturePhase<Int>.possible(nil))
            var storedValue = 5
            var locationSets: [GestureStateLocationSet] = []
            var resetEvents: [GestureStateResetEvent] = []
            var state = GestureState<Int>(wrappedValue: 5) { value, transaction in
                resetEvents.append(.init(value: value, tracksVelocity: transaction.tracksVelocity))
                transaction[GestureStateResetMarkerKey.self] = 99
            }
            state._location = LocationBox(location: FunctionalLocation<Int>(
                get: { storedValue },
                set: { newValue, transaction in
                    storedValue = newValue
                    locationSets.append(.init(
                        value: newValue,
                        tracksVelocity: transaction.tracksVelocity,
                        bodyMarker: transaction[GestureStateBodyMarkerKey.self],
                        resetMarker: transaction[GestureStateResetMarkerKey.self]
                    ))
                }
            ))
            let gesture = ControlledGesture(phase: phase)
                .updating(state) { value, current, transaction in
                    XCTAssertTrue(transaction.tracksVelocity)
                    transaction[GestureStateBodyMarkerKey.self] = value
                    current = value + 10
                }
            let gestureAttr = graph.makeInput(value: gesture)

            _ = type(of: gesture)._makeGesture(
                gesture: _GraphValue(_attribute: gestureAttr),
                inputs: makeGestureInputs(graph: graph)
            )

            Update.ensure {
                phase.setValue(.active(7))
            }

            XCTAssertEqual(storedValue, 17)
            XCTAssertEqual(locationSets, [
                .init(value: 17, tracksVelocity: true, bodyMarker: 7, resetMarker: 0)
            ])

            Update.ensure {
                phase.setValue(.ended(7))
            }

            XCTAssertEqual(storedValue, 5)
            XCTAssertEqual(resetEvents, [
                .init(value: 17, tracksVelocity: true)
            ])
            XCTAssertEqual(locationSets, [
                .init(value: 17, tracksVelocity: true, bodyMarker: 7, resetMarker: 0),
                .init(value: 5, tracksVelocity: true, bodyMarker: 0, resetMarker: 99)
            ])
        }
    }

    private func makeGestureInputs(
        graph: _AGGraph,
        usesGestureGraph: Bool = false
    ) -> _GestureInputs {
        var inputs = _GestureInputs(
            makeViewInputs(graph: graph),
            viewSubgraph: nil,
            events: graph.makeInput(value: [:] as [EventID: any EventType]),
            time: graph.makeInput(value: Time()),
            resetSeed: graph.makeInput(value: UInt32(0)),
            inheritedPhase: graph.makeInput(value: _GestureInputs.InheritedPhase.defaultValue),
            gesturePreferenceKeys: graph.makeInput(value: PreferenceKeys())
        )
        if usesGestureGraph {
            inputs.options = .gestureGraph
        }
        return inputs
    }

    private func drainGestureGraphActions(_ gestureGraph: GestureGraph) {
        for _ in 0..<8 {
            let actions = gestureGraph.data.graph.actionOutbox
            guard !actions.isEmpty else { return }
            gestureGraph.data.graph.actionOutbox.removeAll()
            actions.forEach { $0() }
        }
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        _ViewInputs(
            base: makeGraphInputs(graph: graph),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform.identity),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(.zero)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }

    private func makeGraphInputs(graph: _AGGraph) -> _GraphInputs {
        _GraphInputs(
            time: graph.makeInput(value: Time()),
            phase: graph.makeInput(value: Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: Transaction())
        )
    }
}

private struct ControlledGesture: Gesture {
    typealias Value = Int
    var phase: Attribute<GesturePhase<Int>>

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Int> {
        _ = inputs
        return _GestureOutputs(phase: gesture._attribute.value.phase)
    }

    typealias Body = Never
}

private struct GestureStateBodyEvent: Equatable {
    var value: Int
    var current: Int
    var tracksVelocity: Bool
}

private struct GestureStateResetEvent: Equatable {
    var value: Int
    var tracksVelocity: Bool
}

private struct GestureStateLocationSet: Equatable {
    var value: Int
    var tracksVelocity: Bool
    var bodyMarker: Int
    var resetMarker: Int
}

private struct GestureStateBodyMarkerKey: TransactionKey {
    static let defaultValue = 0
}

private struct GestureStateResetMarkerKey: TransactionKey {
    static let defaultValue = 0
}
