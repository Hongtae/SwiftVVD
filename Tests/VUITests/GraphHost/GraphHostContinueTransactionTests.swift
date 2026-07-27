import XCTest
@testable import VUI

final class GraphHostContinueTransactionTests: XCTestCase {
    func testContinueTransactionQueuesOnUpdatingHostUntilFinish() {
        let host = GraphHost()
        var events: [String] = []

        host.runTransaction (nil, do: {
            host.continueTransaction(
                ContinueRecordingGraphMutation {
                    XCTAssertTrue(host.isUpdating)
                    events.append("mutation")
                }
            )

            XCTAssertTrue(events.isEmpty)
            XCTAssertTrue(host.needsTransaction)
            XCTAssertTrue(host.needsTransaction)
        }, id: nil)

        XCTAssertEqual(events, ["mutation"])
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.isUpdating)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionCombinesWithLastQueuedMutation() {
        let host = GraphHost()
        let storage = ContinueCombineStorage()

        host.runTransaction (nil, do: {
            host.continueTransaction(CombiningContinueMutation(name: "first", storage: storage))
            host.continueTransaction(CombiningContinueMutation(name: "second", storage: storage))

            XCTAssertEqual(storage.events, ["combine:first+second"])
            XCTAssertTrue(host.needsTransaction)
        }, id: nil)

        XCTAssertEqual(storage.events, ["combine:first+second", "apply:first+second"])
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.needsTransaction)
    }

    func testContinueTransactionWalksToUpdatingParentHost() {
        let parent = GraphHost()
        let child = ChildGraphHost(parent: parent)
        var events: [String] = []

        parent.runTransaction (nil, do: {
            child.continueTransaction(
                ContinueRecordingGraphMutation {
                    XCTAssertTrue(parent.isUpdating)
                    XCTAssertFalse(child.isUpdating)
                    XCTAssertTrue(_AGGraph.current === child.graph)
                    events.append("parent")
                }
            )

            XCTAssertTrue(parent.needsTransaction)
            XCTAssertFalse(child.needsTransaction)
        }, id: nil)

        XCTAssertEqual(events, ["parent"])
        XCTAssertFalse(parent.needsTransaction)
        XCTAssertFalse(parent.needsTransaction)
    }

    func testContinueTransactionSettingChildAttributeUsesChildGraphWhenParentIsUpdating() {
        let parent = GraphHost()
        let child = ChildGraphHost(parent: parent)
        var parentAttribute: Attribute<Int>!
        var childAttribute: Attribute<Int>!
        var childWeakAttribute: WeakAttribute<Int>!

        parent.data.withCurrent {
            parentAttribute = parent.graph.makeInput(value: 11)
        }
        child.data.withCurrent {
            childAttribute = child.graph.makeInput(value: 21)
            childWeakAttribute = childAttribute.asWeak()
        }

        XCTAssertEqual(parentAttribute.identifier.rawValue, childAttribute.identifier.rawValue)

        parent.runTransaction(nil, do: {
            child.continueTransaction(setting: childWeakAttribute, to: 22)
            XCTAssertTrue(parent.needsTransaction)
            XCTAssertFalse(child.needsTransaction)
        }, id: nil)

        parent.data.withCurrent {
            XCTAssertEqual(parentAttribute.value, 11)
        }
        child.data.withCurrent {
            XCTAssertEqual(childAttribute.value, 22)
        }
    }

    func testContinueTransactionInvalidatingChildAttributeUsesChildGraphWhenParentIsUpdating() {
        let parent = GraphHost()
        let child = ChildGraphHost(parent: parent)
        var parentInput: Attribute<Int>!
        var childInput: Attribute<Int>!
        var childOutput: Attribute<Int>!
        var childWeakInput: AGWeakAttribute!
        var childEvaluations = 0

        parent.data.withCurrent {
            parentInput = parent.graph.makeInput(value: 7)
        }
        child.data.withCurrent {
            childInput = child.graph.makeInput(value: 3)
            childOutput = child.graph.makeRule {
                childEvaluations += 1
                return childInput.value * 2
            }
            childWeakInput = childInput.asWeak().base
            XCTAssertEqual(childOutput.value, 6)
        }

        XCTAssertEqual(parentInput.identifier.rawValue, childInput.identifier.rawValue)

        parent.runTransaction(nil, do: {
            child.continueTransaction(invalidating: childWeakInput)
            XCTAssertEqual(childEvaluations, 1)
        }, id: nil)

        parent.data.withCurrent {
            XCTAssertEqual(parentInput.value, 7)
        }
        child.data.withCurrent {
            XCTAssertEqual(childOutput.value, 6)
            XCTAssertEqual(childEvaluations, 2)
        }
    }

    func testContinueTransactionInvalidatingCarriesTheActiveHostTransaction() throws {
        let host = GraphHost()
        var input: Attribute<Int>!
        var output: Attribute<Int>!
        var weakInput: AGWeakAttribute!

        host.data.withCurrent {
            input = host.graph.makeInput(value: 3)
            output = host.graph.makeRule {
                input.value * 2
            }
            weakInput = input.asWeak().base
            XCTAssertEqual(output.value, 6)
            XCTAssertNil(host.graph.transaction(for: output.identifier))
        }

        var transaction = Transaction()
        transaction[ContinueTransactionKey.self] = 57
        host.runTransaction(transaction, do: {
            XCTAssertTrue(Transaction.current.isEmpty)
            host.continueTransaction(invalidating: weakInput)
        }, id: nil)

        try host.data.withCurrent {
            let propagated = try XCTUnwrap(
                host.graph.transaction(for: output.identifier)
            )
            XCTAssertEqual(propagated[ContinueTransactionKey.self], 57)
            XCTAssertEqual(output.value, 6)
        }
    }

    // ASSERTIONS animationLabStatusTransactionIsolationRuntimeObserved
    func testPlainContinueTransactionInvalidationClearsPreviousTransaction() throws {
        let host = GraphHost()
        var input: Attribute<Int>!
        var output: Attribute<Int>!
        var weakInput: AGWeakAttribute!
        var evaluations = 0

        host.data.withCurrent {
            input = host.graph.makeInput(value: 3)
            output = host.graph.makeRule {
                evaluations += 1
                return input.value * 2
            }
            weakInput = input.asWeak().base
            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 1)
        }

        var animatedTransaction = Transaction(animation: .linear(duration: 1))
        animatedTransaction[ContinueTransactionKey.self] = 57
        host.runTransaction(animatedTransaction, do: {
            host.continueTransaction(invalidating: weakInput)
        }, id: nil)

        try host.data.withCurrent {
            let propagated = try XCTUnwrap(
                host.graph.transaction(for: output.identifier)
            )
            XCTAssertEqual(propagated[ContinueTransactionKey.self], 57)
            XCTAssertNotNil(propagated.effectiveAnimation)
        }

        host.runTransaction(Transaction(), do: {
            host.continueTransaction(invalidating: weakInput)
        }, id: nil)

        host.data.withCurrent {
            XCTAssertNil(host.graph.transaction(for: output.identifier))
            XCTAssertEqual(
                evaluations,
                1,
                "Transaction provenance clearing must not eagerly evaluate an unused rule."
            )
            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 2)
        }
    }

    func testContinueTransactionWithoutUpdatingHostUsesUpdateActionFallback() {
        let host = GraphHost()
        var events: [String] = []

        host.continueTransaction(
            ContinueRecordingGraphMutation {
                events.append(Update.isActive ? "active" : "inactive")
            }
        )

        XCTAssertEqual(events, [])
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.needsTransaction)
        XCTAssertEqual(host.data.transactionSeed, 0)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertEqual(events, ["active"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionWithoutUpdatingHostFallbackQueuesExpectedReason() {
        let host = GraphHost()
        var events: [String] = []

        Update.begin()
        defer {
            if Update.isActive {
                Update.end()
            }
        }

        host.continueTransaction(
            ContinueRecordingGraphMutation {
                events.append(Update.isActive ? "active" : "inactive")
            }
        )

        XCTAssertEqual(Update.queuedActionReasons, [nil])
        XCTAssertEqual(events, [])

        Update.end()

        XCTAssertEqual(events, [])
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.needsTransaction)
        XCTAssertEqual(host.data.transactionSeed, 0)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertEqual(events, ["active"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionWithoutUpdatingHostFallbackAppliesInHostGraphContext() {
        let host = GraphHost()
        var attribute: Attribute<Int>!
        var weakAttribute: WeakAttribute<Int>!
        host.data.withCurrent {
            attribute = host.data.graph.makeInput(value: 1)
            weakAttribute = attribute.asWeak()
        }

        host.continueTransaction(setting: weakAttribute, to: 2)

        host.data.withCurrent {
            XCTAssertEqual(attribute.value, 1)
        }
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(attribute.value, 2)
        }
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionInvalidatingFallbackCapturesCurrentTransactionBeforeUpdateAction() {
        let host = GraphHost()
        var input: Attribute<Int>!
        var output: Attribute<Int>!
        var weakInput: AGWeakAttribute!
        var evaluations = 0

        host.data.withCurrent {
            input = host.data.graph.makeInput(value: 3)
            output = host.data.graph.makeRule {
                evaluations += 1
                return input.value * 2
            }
            weakInput = input.asWeak().base

            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 1)
            XCTAssertNil(host.data.graph.transaction(for: output.identifier))
        }

        var transaction = Transaction()
        transaction[ContinueTransactionKey.self] = 42

        Update.begin()
        defer {
            if Update.isActive {
                Update.end()
            }
        }

        withTransaction(transaction) {
            host.continueTransaction(invalidating: weakInput)
        }

        XCTAssertEqual(Update.queuedActionReasons, [nil])
        XCTAssertFalse(host.hasPendingTransactions)

        Update.end()

        XCTAssertTrue(Transaction.current.isEmpty)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        host.data.withCurrent {
            let propagated = host.data.graph.transaction(for: output.identifier)
            XCTAssertEqual(propagated?[ContinueTransactionKey.self], 42)
            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 2)
        }
    }

    func testContinueTransactionInvalidatingFallbackDoesNotFinalizeCapturedCompletionListeners() {
        Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        ).forEach { $0() }

        let host = GraphHost()
        var input: Attribute<Int>!
        var output: Attribute<Int>!
        var weakInput: AGWeakAttribute!
        var evaluations = 0
        var events: [String] = []

        host.data.withCurrent {
            input = host.data.graph.makeInput(value: 3)
            output = host.data.graph.makeRule {
                evaluations += 1
                return input.value * 2
            }
            weakInput = input.asWeak().base

            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 1)
        }

        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("completion")
        }

        Update.begin()
        defer {
            if Update.isActive {
                Update.end()
            }
        }

        let previousBox = Transaction.ThreadStorage.currentBox
        Transaction.ThreadStorage.currentBox = Transaction.ThreadStorageBox(transaction: transaction)
        do {
            host.continueTransaction(invalidating: weakInput)
            XCTAssertFalse(host.hasPendingTransactions)
        }
        Transaction.ThreadStorage.currentBox = previousBox

        XCTAssertEqual(Update.queuedActionReasons, [nil])

        Update.end()

        XCTAssertTrue(host.hasPendingTransactions)
        XCTAssertTrue(events.isEmpty)

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 2)
        }
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(host.hasPendingTransactions)

        Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        ).forEach { $0() }
        XCTAssertEqual(events, ["completion"])

        withExtendedLifetime(transaction) {}
    }

    func testContinueTransactionGenericFallbackDoesNotCaptureAmbientTransaction() {
        let host = GraphHost()
        var observed: [Int] = []
        var transaction = Transaction()
        transaction[ContinueTransactionKey.self] = 87

        withTransaction(transaction) {
            host.continueTransaction(
                ContinueRecordingGraphMutation {
                    observed.append(Transaction.current[ContinueTransactionKey.self])
                }
            )

            XCTAssertTrue(host.hasPendingTransactions)
            XCTAssertTrue(observed.isEmpty)
        }

        XCTAssertTrue(Transaction.current.isEmpty)
        host.flushTransactions()

        XCTAssertEqual(observed, [0])
        XCTAssertFalse(host.hasPendingTransactions)
    }

    func testContinueTransactionSettingFallbackDoesNotCaptureAmbientTransaction() {
        let host = GraphHost()
        var attribute: Attribute<Int>!
        var weakAttribute: WeakAttribute<Int>!
        host.data.withCurrent {
            attribute = host.data.graph.makeInput(value: 1)
            weakAttribute = attribute.asWeak()
        }

        var transaction = Transaction()
        transaction[ContinueTransactionKey.self] = 99
        withTransaction(transaction) {
            host.continueTransaction(setting: weakAttribute, to: 2)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        XCTAssertTrue(Transaction.current.isEmpty)
        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(attribute.value, 2)
            XCTAssertNil(host.data.graph.transaction(for: attribute.identifier))
        }
        XCTAssertFalse(host.hasPendingTransactions)
    }

    func testContinueTransactionWithoutUpdatingHostFallbackBatchesThroughAsyncTransaction() {
        let host = GraphHost()
        var events: [String] = []

        host.continueTransaction(
            ContinueRecordingGraphMutation {
                XCTAssertTrue(host.isUpdating)
                events.append("first")
            }
        )
        host.continueTransaction(
            ContinueRecordingGraphMutation {
                XCTAssertTrue(host.isUpdating)
                events.append("second")
            }
        )

        XCTAssertTrue(host.hasPendingTransactions)
        XCTAssertEqual(events, [])

        host.flushTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionSettingWeakAttributeAppliesWhenTransactionFinishes() {
        let host = GraphHost()
        var attribute: Attribute<Int>!
        var weakAttribute: WeakAttribute<Int>!
        host.data.withCurrent {
            attribute = host.data.graph.makeInput(value: 1)
            weakAttribute = attribute.asWeak()
        }

        host.runTransaction (nil, do: {
            host.continueTransaction(setting: weakAttribute, to: 2)
            XCTAssertEqual(attribute.value, 1)
            XCTAssertTrue(host.needsTransaction)
        }, id: nil)

        host.data.withCurrent {
            XCTAssertEqual(attribute.value, 2)
        }
    }

    func testContinueTransactionInvalidatingWeakAttributeMarksDependentsDirtyAtFinish() {
        let host = GraphHost()
        var input: Attribute<Int>!
        var output: Attribute<Int>!
        var weakInput: AGWeakAttribute!
        var evaluations = 0

        host.data.withCurrent {
            input = host.data.graph.makeInput(value: 3)
            output = host.data.graph.makeRule {
                evaluations += 1
                return input.value * 2
            }
            weakInput = input.asWeak().base

            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 1)
        }

        host.runTransaction (nil, do: {
            host.continueTransaction(invalidating: weakInput)
            XCTAssertEqual(evaluations, 1)
        }, id: nil)

        host.data.withCurrent {
            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 2)
        }
    }
}

private final class ChildGraphHost: GraphHost {
    weak var parent: GraphHost?

    init(parent: GraphHost) {
        self.parent = parent
        super.init(data: Data())
    }

    override var parentHost: GraphHost? {
        parent
    }
}

private struct ContinueRecordingGraphMutation: GraphMutation {
    var body: () -> Void

    func apply() {
        body()
    }
}

private final class ContinueCombineStorage {
    var events: [String] = []
}

private struct ContinueTransactionKey: TransactionKey {
    static let defaultValue = 0
}

private struct CombiningContinueMutation: GraphMutation {
    var name: String
    var storage: ContinueCombineStorage

    func apply() {
        storage.events.append("apply:\(name)")
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? CombiningContinueMutation else {
            return false
        }
        storage.events.append("combine:\(name)+\(mutation.name)")
        name += "+\(mutation.name)"
        return true
    }
}
