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

        var ambient = Transaction(animation: .linear(duration: 0.40))
        ambient.disablesAnimations = false
        withTransaction(ambient) {
            binding.value.transaction(local).wrappedValue = 3
        }

        XCTAssertEqual(recorder.value, BindingPropagationModel(value: 3))
        XCTAssertEqual(
            recorder.transactions,
            [
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: true),
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

        let baseLocal = binding.transaction(Transaction(animation: .linear(duration: 0.30)))
        baseLocal[0].wrappedValue = 3

        var ambient = Transaction(animation: .linear(duration: 0.40))
        ambient.disablesAnimations = false
        withTransaction(ambient) {
            binding[0].transaction(local).wrappedValue = 4
        }

        XCTAssertEqual(recorder.value, [4])
        XCTAssertEqual(
            recorder.transactions,
            [
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
            ]
        )
    }

    func testCollectionDynamicMemberBindingKeepsCollectionTransactionBoundary() {
        let recorder = BindingPropagationRecorder([BindingPropagationModel(value: 0)])
        let binding = recorder.binding

        binding[0].value.wrappedValue = 1

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        binding[0].value.transaction(local).wrappedValue = 2

        let baseLocal = binding.transaction(Transaction(animation: .linear(duration: 0.30)))
        baseLocal[0].value.wrappedValue = 3

        var ambient = Transaction(animation: .linear(duration: 0.40))
        ambient.disablesAnimations = false
        withTransaction(ambient) {
            binding[0].value.transaction(local).wrappedValue = 4
        }

        XCTAssertEqual(recorder.value, [BindingPropagationModel(value: 4)])
        XCTAssertEqual(
            recorder.transactions,
            [
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
            ]
        )
    }
}
