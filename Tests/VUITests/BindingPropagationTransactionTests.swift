import XCTest
@testable import VUI

private struct BindingPropagationSnapshot: Equatable {
    var hasAnimation: Bool
    var disablesAnimations: Bool
}

private final class BindingPropagationRecorder<Value> {
    var value: Value
    var transactions: [BindingPropagationSnapshot] = []

    init(_ value: Value) {
        self.value = value
    }

    var binding: Binding<Value> {
        Binding<Value>(
            get: { self.value },
            set: { newValue, transaction in
                self.transactions.append(Self.snapshot(transaction))
                self.value = newValue
            }
        )
    }

    static func snapshot(_ transaction: Transaction) -> BindingPropagationSnapshot {
        BindingPropagationSnapshot(
            hasAnimation: transaction.animation != nil,
            disablesAnimations: transaction.disablesAnimations
        )
    }
}

private struct BindingPropagationModel: Equatable {
    var value: Double
}

final class BindingPropagationTransactionTests: XCTestCase {
    func testDynamicMemberBindingForwardsChildLocalTransaction() {
        let recorder = BindingPropagationRecorder(BindingPropagationModel(value: 0))
        let binding = recorder.binding

        binding.value.wrappedValue = 1

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        binding.value.transaction(local).wrappedValue = 2

        binding.value.animation(.linear(duration: 0.25)).wrappedValue = 3

        var ambient = Transaction(animation: .linear(duration: 0.40))
        ambient.disablesAnimations = false
        withTransaction(ambient) {
            binding.value.transaction(local).wrappedValue = 4
        }

        XCTAssertEqual(recorder.value, BindingPropagationModel(value: 4))
        XCTAssertEqual(
            recorder.transactions,
            [
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: true),
                .init(hasAnimation: true, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
            ]
        )
    }

    func testCollectionElementBindingKeepsCollectionTransactionBoundary() {
        let recorder = BindingPropagationRecorder([0.0])
        let binding = recorder.binding

        binding[0].wrappedValue = 1

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        binding[0].transaction(local).wrappedValue = 2

        binding[0].animation(.linear(duration: 0.25)).wrappedValue = 3

        let baseLocal = binding.transaction(Transaction(animation: .linear(duration: 0.30)))
        baseLocal[0].wrappedValue = 4

        var ambient = Transaction(animation: .linear(duration: 0.40))
        ambient.disablesAnimations = false
        withTransaction(ambient) {
            binding[0].transaction(local).wrappedValue = 5
        }

        XCTAssertEqual(recorder.value, [5])
        XCTAssertEqual(
            recorder.transactions,
            [
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
            ]
        )
    }

    func testCollectionElementLocalCompletionFallsBackWhenLocalTransactionIsIgnored() {
        let recorder = BindingPropagationRecorder([0.0])
        let binding = recorder.binding
        var events: [String] = []

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        local.addAnimationCompletion(criteria: .removed) {
            events.append("local removed")
        }

        binding[0].transaction(local).wrappedValue = 1
        events.append("returned")

        XCTAssertEqual(recorder.value, [1])
        XCTAssertEqual(
            recorder.transactions,
            [.init(hasAnimation: false, disablesAnimations: false)]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(events, ["returned", "local removed"])
    }

    func testCollectionDynamicMemberBindingKeepsCollectionTransactionBoundary() {
        let recorder = BindingPropagationRecorder([BindingPropagationModel(value: 0)])
        let binding = recorder.binding

        binding[0].value.wrappedValue = 1

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        binding[0].value.transaction(local).wrappedValue = 2

        binding[0].value.animation(.linear(duration: 0.25)).wrappedValue = 3

        let baseLocal = binding.transaction(Transaction(animation: .linear(duration: 0.30)))
        baseLocal[0].value.wrappedValue = 4

        var ambient = Transaction(animation: .linear(duration: 0.40))
        ambient.disablesAnimations = false
        withTransaction(ambient) {
            binding[0].value.transaction(local).wrappedValue = 5
        }

        XCTAssertEqual(recorder.value, [BindingPropagationModel(value: 5)])
        XCTAssertEqual(
            recorder.transactions,
            [
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
            ]
        )
    }

    func testCollectionDynamicMemberLocalCompletionFallsBackWhenLocalTransactionIsIgnored() {
        let recorder = BindingPropagationRecorder([BindingPropagationModel(value: 0)])
        let binding = recorder.binding
        var events: [String] = []

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        local.addAnimationCompletion(criteria: .removed) {
            events.append("local removed")
        }

        binding[0].value.transaction(local).wrappedValue = 1
        events.append("returned")

        XCTAssertEqual(recorder.value, [BindingPropagationModel(value: 1)])
        XCTAssertEqual(
            recorder.transactions,
            [.init(hasAnimation: false, disablesAnimations: false)]
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(events, ["returned", "local removed"])
    }
}
