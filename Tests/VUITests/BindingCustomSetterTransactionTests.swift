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

    func testAmbientTransactionOwnsAnimatableWriteInsideBindingLocalCustomSetter() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        var events: [String] = []
        let binding = Binding<Double>(
            get: { 0 },
            set: { newValue, transaction in
                let current = Transaction.current
                events.append(transaction.disablesAnimations ? "setter local argument" : "setter ambient argument")
                events.append(current.animation == nil ? "setter current empty" : "setter current ambient")
                harness.setSource(_OpacityEffect(opacity: newValue), transaction: current)
            }
        )

        var local = Transaction(animation: .linear(duration: 0.20))
        local.disablesAnimations = true
        local.addAnimationCompletion(criteria: .removed) {
            events.append("local completion")
        }
        var ambient = Transaction(animation: .linear(duration: 0.20))
        ambient.addAnimationCompletion(criteria: .removed) {
            events.append("ambient completion")
        }

        withTransaction(ambient) {
            binding.transaction(local).wrappedValue = 1
            events.append("body")
            XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        }
        events.append("returned")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        harness.flushCompletionActions()
        XCTAssertEqual(
            events,
            [
                "setter local argument",
                "setter current ambient",
                "body",
                "returned",
                "local completion",
            ]
        )

        for time in stride(from: 1.0 / 60.0, through: 0.35, by: 1.0 / 60.0) {
            harness.setTime(time)
            _ = harness.currentValue()
        }
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(
            events,
            [
                "setter local argument",
                "setter current ambient",
                "body",
                "returned",
                "local completion",
                "ambient completion",
            ]
        )
    }
}
