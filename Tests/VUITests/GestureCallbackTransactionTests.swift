import XCTest
@testable import VUI

final class GestureCallbackTransactionTests: XCTestCase {
    func testCallbacksPhaseCarriesRemovableAttributeMarker() {
        assertRemovableAttribute(CallbacksPhase<ChangedCallbacks<Int>>.self)
    }

    func testChangedCallbacksReturnDeferredActionCapturingValue() {
        var observed: [Int] = []
        let callbacks = ChangedCallbacks<Int> { value in
            observed.append(value)
        }
        var state: Void = ChangedCallbacks<Int>.initialState

        let action = callbacks.dispatch(phase: .active(8), state: &state)

        XCTAssertEqual(observed, [])
        XCTAssertNotNil(action)
        action?()
        XCTAssertEqual(observed, [8])
        XCTAssertNil(callbacks.dispatch(phase: .possible(nil), state: &state))
    }

    func testFailedCallbacksReturnDeferredAction() {
        var callbackCount = 0
        let callbacks = FailedCallbacks<Int> {
            callbackCount += 1
        }
        var state: Void = FailedCallbacks<Int>.initialState

        let action = callbacks.dispatch(phase: .failed, state: &state)

        XCTAssertEqual(callbackCount, 0)
        XCTAssertNotNil(action)
        action?()
        XCTAssertEqual(callbackCount, 1)
        XCTAssertNil(callbacks.dispatch(phase: .active(3), state: &state))
    }

    func testCallbacksPhaseFallbackQueuesReturnedActionThroughUpdate() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let phase = graph.makeInput(value: GesturePhase<Int>.possible(nil))
            let resetSeed = graph.makeInput(value: UInt32.zero)
            var observed: [Int] = []
            let modifier = graph.makeInput(value: CallbacksGesture(
                callbacks: ChangedCallbacks<Int> { value in
                    observed.append(value)
                }
            ))
            let callbackPhase = CallbacksPhase<ChangedCallbacks<Int>>(
                modifierAttr: modifier,
                phaseAttr: phase,
                resetSeedAttr: resetSeed,
                useGestureGraph: false,
                gestureGraph: nil
            )
            let output = graph.makeStatefulRule(callbackPhase)

            Update.ensure {
                phase.setValue(.active(12))
                _ = output.value
                XCTAssertEqual(observed, [])
            }

            XCTAssertEqual(observed, [12])
        }
    }

    func testFullGestureCallbacksChangedReturnsValueCapturingTracksVelocityScopedAction() {
        var observed: [(value: Int, tracksVelocity: Bool, parentKey: Int)] = []
        let callbacks = FullGestureCallbacks<Int>(
            possible: nil,
            changed: { value in
                observed.append((
                    value: value,
                    tracksVelocity: Transaction.current.tracksVelocity,
                    parentKey: Transaction.current[GestureCallbackParentKey.self]
                ))
            },
            ended: nil,
            failed: nil
        )
        var state = FullGestureCallbacks<Int>.initialState

        let first = callbacks.dispatch(phase: .active(3), state: &state)
        let second = callbacks.dispatch(phase: .active(4), state: &state)

        XCTAssertEqual(observed.count, 0)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        var parent = Transaction()
        parent[GestureCallbackParentKey.self] = 7
        Transaction.withScopedThreadTransaction(parent) {
            first?()
        }
        parent[GestureCallbackParentKey.self] = 11
        Transaction.withScopedThreadTransaction(parent) {
            second?()
        }
        XCTAssertEqual(observed.map(\.value), [3, 4])
        XCTAssertEqual(observed.map(\.tracksVelocity), [true, true])
        XCTAssertEqual(observed.map(\.parentKey), [7, 11])
        XCTAssertEqual(state.lastPhase, .active(4))
    }

    func testFullGestureCallbacksPossibleReturnsDeferredActionAndResetsActiveMarker() {
        var observed: [Int?] = []
        let callbacks = FullGestureCallbacks<Int>(
            possible: { value in observed.append(value) },
            changed: nil,
            ended: nil,
            failed: nil
        )
        var state = FullGestureCallbacks<Int>.initialState

        let active = callbacks.dispatch(phase: .active(3), state: &state)
        XCTAssertNil(active)
        XCTAssertTrue(state.hasBecomeActive)

        let possible = callbacks.dispatch(phase: .possible(7), state: &state)

        XCTAssertEqual(observed, [])
        XCTAssertNotNil(possible)
        XCTAssertFalse(state.hasBecomeActive)
        possible?()
        XCTAssertEqual(observed, [7])
        XCTAssertNil(callbacks.dispatch(phase: .possible(7), state: &state))
    }

    func testFullGestureCallbacksTerminalsUsePhaseChangeGateNotLocalHasFiredGuard() {
        var observed: [String] = []
        let callbacks = FullGestureCallbacks<Int>(
            possible: nil,
            changed: nil,
            ended: { value in observed.append("ended:\(value)") },
            failed: { observed.append("failed") }
        )
        var state = FullGestureCallbacks<Int>.initialState

        let ended = callbacks.dispatch(phase: .ended(4), state: &state)
        XCTAssertNotNil(ended)
        ended?()
        XCTAssertEqual(observed, ["ended:4"])

        XCTAssertNil(callbacks.dispatch(phase: .ended(4), state: &state))

        let failed = callbacks.dispatch(phase: .failed, state: &state)
        XCTAssertNotNil(failed)
        failed?()
        XCTAssertEqual(observed, ["ended:4", "failed"])
    }

    func testFullGestureCallbacksUnchangedActiveDoesNotReturnAction() {
        var callbackCount = 0
        let callbacks = FullGestureCallbacks<Int>(
            possible: nil,
            changed: { _ in callbackCount += 1 },
            ended: nil,
            failed: nil
        )
        var state = FullGestureCallbacks<Int>.initialState

        let first = callbacks.dispatch(phase: .active(4), state: &state)
        first?()
        let second = callbacks.dispatch(phase: .active(4), state: &state)

        XCTAssertEqual(callbackCount, 1)
        XCTAssertNil(second)
    }

    func testPressableGestureCallbacksEndedClearsPressingBeforePressed() {
        var observed: [String] = []
        let callbacks = PressableGestureCallbacks<Int>(
            pressing: { observed.append("pressing:\($0)") },
            pressed: { observed.append("pressed") }
        )
        var state = PressableGestureCallbacks<Int>.initialState

        let active = callbacks.dispatch(phase: .active(1), state: &state)
        XCTAssertTrue(state)
        active?()
        XCTAssertEqual(observed, ["pressing:true"])

        let ended = callbacks.dispatch(phase: .ended(1), state: &state)

        XCTAssertFalse(state)
        XCTAssertEqual(observed, ["pressing:true"])
        ended?()
        XCTAssertEqual(observed, ["pressing:true", "pressing:false", "pressed"])
    }

    func testPressableGestureCallbacksFailedOnlyClearsPressing() {
        var observed: [String] = []
        let callbacks = PressableGestureCallbacks<Int>(
            pressing: { observed.append("pressing:\($0)") },
            pressed: { observed.append("pressed") }
        )
        var state = true

        let failed = callbacks.dispatch(phase: .failed, state: &state)

        XCTAssertFalse(state)
        failed?()
        XCTAssertEqual(observed, ["pressing:false"])
    }
}

private struct GestureCallbackParentKey: TransactionKey {
    static let defaultValue: Int = 0
}

private func assertRemovableAttribute<T: RemovableAttribute>(_ type: T.Type) {}
