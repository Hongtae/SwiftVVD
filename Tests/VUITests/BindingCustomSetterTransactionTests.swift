import XCTest
@testable import VUI

final class BindingCustomSetterTransactionTests: XCTestCase {
    func testCustomNoopSetterDoesNotMarkScopedTransactionMutated() {
        var events: [String] = []
        let binding = Binding<Double>(
            get: { 0 },
            set: { _ in
                events.append("setter")
            }
        )

        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("completion")
        }

        withTransaction(transaction) {
            binding.wrappedValue = 1
            events.append("body")
        }
        events.append("returned")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(events, ["setter", "body", "returned", "completion"])
    }

    func testTransactionAwareNoopSetterDoesNotMarkScopedTransactionMutated() {
        var events: [String] = []
        let binding = Binding<Double>(
            get: { 0 },
            set: { _, transaction in
                events.append(transaction.animation == nil ? "setter nil" : "setter animated")
            }
        )

        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("completion")
        }

        withTransaction(transaction) {
            binding.wrappedValue = 1
            events.append("body")
        }
        events.append("returned")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(events, ["setter nil", "body", "returned", "completion"])
    }

    func testTransactionAwareSetterReceivesBindingLocalTransaction() {
        var records: [String] = []
        let binding = Binding<Double>(
            get: { 0 },
            set: { _, transaction in
                let argument = transaction.animation == nil ? "argument nil" : "argument animated"
                let disables = transaction.disablesAnimations ? "disabled" : "enabled"
                let current = Transaction.current.animation == nil ? "current nil" : "current animated"
                records.append("\(argument) \(disables) \(current)")
            }
        )

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        var ambient = Transaction(animation: .linear(duration: 0.60))
        ambient.addAnimationCompletion(criteria: .removed) {}

        binding.wrappedValue = 1
        binding.transaction(local).wrappedValue = 2
        withTransaction(ambient) {
            binding.wrappedValue = 3
        }
        withTransaction(ambient) {
            binding.transaction(local).wrappedValue = 4
        }

        XCTAssertEqual(
            records,
            [
                "argument nil enabled current nil",
                "argument animated disabled current nil",
                "argument nil enabled current animated",
                "argument animated disabled current animated",
            ]
        )
    }

    func testBindingLocalCustomSetterDoesNotInstallActiveTransactionScope() {
        var events: [String] = []
        let binding = Binding<Double>(
            get: { 0 },
            set: { _ in
                events.append(Transaction.current.isEmpty ? "setter current empty" : "setter current active")
                Transaction.ThreadStorage.markMutation(for: Transaction.current)
            }
        )

        do {
            var local = Transaction(animation: .linear(duration: 0.20))
            local.addAnimationCompletion(criteria: .removed) {
                events.append("local completion")
            }
            binding.transaction(local).wrappedValue = 1
            events.append("returned")
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(
            events,
            [
                "setter current empty",
                "returned",
                "local completion",
            ]
        )
    }

    func testAmbientTransactionOwnsNestedCustomSetterMutation() {
        var events: [String] = []
        let binding = Binding<Double>(
            get: { 0 },
            set: { _ in
                events.append("setter")
                Transaction.ThreadStorage.markMutation(for: Transaction.current)
            }
        )

        var ambient = Transaction(animation: .linear(duration: 0.20))
        ambient.addAnimationCompletion(criteria: .removed) {
            events.append("ambient completion")
        }

        withTransaction(ambient) {
            binding.wrappedValue = 1
            events.append("body")
        }
        events.append("returned")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(events, ["setter", "body", "returned"])

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        XCTAssertEqual(events, ["setter", "body", "returned", "ambient completion"])
    }
}
