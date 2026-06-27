import XCTest
@testable import VUI

final class GestureCallbackTransactionTests: XCTestCase {
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
}

private struct GestureCallbackParentKey: TransactionKey {
    static let defaultValue: Int = 0
}
