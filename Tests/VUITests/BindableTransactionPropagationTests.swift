import Observation
import XCTest
@testable import VUI

@Observable
private final class BindableTransactionModel {
    var localValue = 0.0
    var ambientValue = 0.0
    var ambientNilValue = 0.0
}

private struct BindableTransactionSnapshot: Equatable {
    var isEmpty: Bool
    var hasAnimation: Bool
    var disablesAnimations: Bool
}

private final class BindableTransactionSnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BindableTransactionSnapshot] = []

    var snapshots: [BindableTransactionSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ snapshot: BindableTransactionSnapshot) {
        lock.lock()
        storage.append(snapshot)
        lock.unlock()
    }
}

final class BindableTransactionPropagationTests: XCTestCase {
    func testLocalTransactionInstallsActiveScopeForObservableInvalidation() {
        let model = BindableTransactionModel()
        let bindable = Bindable(model)
        let recorder = BindableTransactionSnapshotRecorder()
        var events: [String] = []

        withObservationTracking {
            _ = model.localValue
        } onChange: {
            recorder.record(Self.snapshot(Transaction.current))
        }

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        local.addAnimationCompletion(criteria: .removed) {
            events.append("local completion")
        }

        bindable.localValue.transaction(local).wrappedValue = 1
        events.append("returned")

        XCTAssertEqual(model.localValue, 1)
        XCTAssertEqual(
            recorder.snapshots,
            [.init(isEmpty: false, hasAnimation: true, disablesAnimations: true)]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(events, ["returned"])

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertEqual(events, ["returned", "local completion"])
    }

    func testAmbientTransactionOwnsBindableMutationWhenLocalTransactionIsPresent() {
        let model = BindableTransactionModel()
        let bindable = Bindable(model)
        let recorder = BindableTransactionSnapshotRecorder()
        var events: [String] = []

        withObservationTracking {
            _ = model.ambientValue
        } onChange: {
            recorder.record(Self.snapshot(Transaction.current))
        }

        var local = Transaction(animation: nil)
        local.disablesAnimations = true
        local.addAnimationCompletion(criteria: .removed) {
            events.append("local completion")
        }

        var ambient = Transaction(animation: .linear(duration: 0.20))
        ambient.addAnimationCompletion(criteria: .removed) {
            events.append("ambient completion")
        }

        withTransaction(ambient) {
            bindable.ambientValue.transaction(local).wrappedValue = 1
            events.append("body")
        }
        events.append("returned")

        XCTAssertEqual(model.ambientValue, 1)
        XCTAssertEqual(
            recorder.snapshots,
            [.init(isEmpty: false, hasAnimation: true, disablesAnimations: false)]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(events, ["body", "returned", "local completion"])

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertEqual(events, ["body", "returned", "local completion", "ambient completion"])
    }

    func testAmbientNilTransactionOverridesBindableLocalAnimation() {
        let model = BindableTransactionModel()
        let bindable = Bindable(model)
        let recorder = BindableTransactionSnapshotRecorder()
        var events: [String] = []

        withObservationTracking {
            _ = model.ambientNilValue
        } onChange: {
            recorder.record(Self.snapshot(Transaction.current))
        }

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        local.addAnimationCompletion(criteria: .removed) {
            events.append("local completion")
        }

        var ambient = Transaction(animation: nil)
        ambient.addAnimationCompletion(criteria: .removed) {
            events.append("ambient completion")
        }

        withTransaction(ambient) {
            bindable.ambientNilValue.transaction(local).wrappedValue = 1
            events.append("body")
        }
        events.append("returned")

        XCTAssertEqual(model.ambientNilValue, 1)
        XCTAssertEqual(
            recorder.snapshots,
            [.init(isEmpty: false, hasAnimation: false, disablesAnimations: false)]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(
            events,
            [
                "body",
                "returned",
                "local completion",
                "ambient completion",
            ]
        )
    }

    private static func snapshot(_ transaction: Transaction) -> BindableTransactionSnapshot {
        BindableTransactionSnapshot(
            isEmpty: transaction.isEmpty,
            hasAnimation: transaction.animation != nil,
            disablesAnimations: transaction.disablesAnimations
        )
    }
}
