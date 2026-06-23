import XCTest
@testable import VUI

private struct BindingTransactionSnapshot: Equatable {
    var hasAnimation: Bool
    var disablesAnimations: Bool
}

private final class BindingTransactionRecorder<Value> {
    var value: Value
    var transactions: [BindingTransactionSnapshot] = []

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

    static func snapshot(_ transaction: Transaction) -> BindingTransactionSnapshot {
        BindingTransactionSnapshot(
            hasAnimation: transaction.animation != nil,
            disablesAnimations: transaction.disablesAnimations
        )
    }
}

final class BindingConversionTransactionTests: XCTestCase {
    func testPromotedOptionalForwardsLocalBaseAndAmbientTransactions() {
        let recorder = BindingTransactionRecorder(10)
        let base = recorder.binding

        Binding<Int?>(base).wrappedValue = 11

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        Binding<Int?>(base).transaction(local).wrappedValue = 12

        let baseLocal = base.transaction(Transaction(animation: .linear(duration: 0.30)))
        let promotedFromBaseLocal = Binding<Int?>(baseLocal)
        promotedFromBaseLocal.wrappedValue = 13
        promotedFromBaseLocal.wrappedValue = nil

        var ambient = Transaction(animation: .linear(duration: 0.40))
        ambient.disablesAnimations = false
        withTransaction(ambient) {
            Binding<Int?>(base).transaction(local).wrappedValue = 14
        }

        XCTAssertEqual(recorder.value, 14)
        XCTAssertEqual(
            recorder.transactions,
            [
                .init(hasAnimation: false, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: true),
                .init(hasAnimation: true, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
                .init(hasAnimation: true, disablesAnimations: false),
            ]
        )
    }

    func testFailableOptionalForwardsLocalBaseAndAmbientTransactions() throws {
        let nilRecorder = BindingTransactionRecorder<Int?>(nil)
        XCTAssertNil(Binding<Int>(nilRecorder.binding))

        let recorder = BindingTransactionRecorder<Int?>(20)
        let base = recorder.binding
        let unwrapped = try XCTUnwrap(Binding<Int>(base))
        unwrapped.wrappedValue = 21

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        unwrapped.transaction(local).wrappedValue = 22

        let baseLocal = base.transaction(Transaction(animation: .linear(duration: 0.30)))
        try XCTUnwrap(Binding<Int>(baseLocal)).wrappedValue = 23

        var ambient = Transaction(animation: .linear(duration: 0.40))
        ambient.disablesAnimations = false
        withTransaction(ambient) {
            unwrapped.transaction(local).wrappedValue = 24
        }

        XCTAssertEqual(recorder.value, 24)
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

    func testAnyHashableForwardsLocalBaseAndAmbientTransactions() {
        let recorder = BindingTransactionRecorder(40)
        let base = recorder.binding
        let erased = Binding<AnyHashable>(base)

        XCTAssertEqual(erased.wrappedValue, AnyHashable(40))
        erased.wrappedValue = AnyHashable(41)

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        erased.transaction(local).wrappedValue = AnyHashable(42)

        let baseLocal = base.transaction(Transaction(animation: .linear(duration: 0.30)))
        Binding<AnyHashable>(baseLocal).wrappedValue = AnyHashable(43)

        var ambient = Transaction(animation: .linear(duration: 0.40))
        ambient.disablesAnimations = false
        withTransaction(ambient) {
            erased.transaction(local).wrappedValue = AnyHashable(44)
        }

        XCTAssertEqual(recorder.value, 44)
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
}
