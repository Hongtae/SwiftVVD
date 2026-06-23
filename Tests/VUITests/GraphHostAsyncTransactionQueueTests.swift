import XCTest
@testable import VUI

final class GraphHostAsyncTransactionQueueTests: XCTestCase {
    func testDeferredAsyncTransactionQueuesUntilFlush() {
        let host = GraphHost()
        var events: [String] = []

        host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 10),
            mutation: RecordingGraphMutation {
                XCTAssertTrue(Update.isActive)
                XCTAssertTrue(host.isUpdating)
                events.append("deferred")
            }
        )

        XCTAssertTrue(host.hasPendingTransactions)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(host.data.transactionSeed, 0)

        host.flushTransactions()

        XCTAssertEqual(events, ["deferred"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertFalse(host.isUpdating)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testDeferredAsyncTransactionFlushKeepsAmbientCurrentTransaction() {
        Transaction.ThreadStorage.currentBox = nil
        let host = GraphHost()
        var child = Transaction()
        child.isContinuous = true
        var observed: (Bool, Bool)?

        host.asyncTransaction(
            child,
            id: Transaction.ID(value: 11),
            mutation: RecordingGraphMutation {
                let current = Transaction.current
                observed = (current.disablesAnimations, current.isContinuous)
            }
        )

        var parent = Transaction()
        parent.disablesAnimations = true
        withTransaction(parent) {
            host.flushTransactions()
            XCTAssertTrue(Transaction.current.disablesAnimations)
            XCTAssertFalse(Transaction.current.isContinuous)
        }

        XCTAssertEqual(observed?.0, true)
        XCTAssertEqual(observed?.1, false)
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testSameTransactionIDAppendsToPendingTransaction() {
        let host = GraphHost()
        var events: [String] = []
        let transaction = Transaction()
        let id = Transaction.ID(value: 12)

        let firstTrace = host.asyncTransaction(
            transaction,
            id: id,
            mutation: RecordingGraphMutation { events.append("first") }
        )
        let secondTrace = host.asyncTransaction(
            transaction,
            id: id,
            mutation: RecordingGraphMutation { events.append("second") }
        )

        XCTAssertEqual(firstTrace, secondTrace)

        host.flushTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testSameTransactionIDCombinesAndMutatesLastPendingMutation() {
        let host = GraphHost()
        let storage = AsyncCombineStorage()
        let transaction = Transaction()
        let id = Transaction.ID(value: 121)

        let firstTrace = host.asyncTransaction(
            transaction,
            id: id,
            mutation: CombiningAsyncMutation(name: "first", storage: storage)
        )
        let secondTrace = host.asyncTransaction(
            transaction,
            id: id,
            mutation: CombiningAsyncMutation(name: "second", storage: storage)
        )

        XCTAssertEqual(firstTrace, secondTrace)
        XCTAssertEqual(storage.events, ["combine:first+second"])

        host.flushTransactions()

        XCTAssertEqual(storage.events, ["combine:first+second", "apply:first+second"])
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testSameTransactionIDWithEqualPropertyListsAppendsToPendingTransaction() {
        let host = GraphHost()
        var events: [String] = []
        let id = Transaction.ID(value: 13)
        var first = Transaction()
        var second = Transaction()
        first[QueueMergeFlagKey.self] = true
        second[QueueMergeFlagKey.self] = true

        let firstTrace = host.asyncTransaction(
            first,
            id: id,
            mutation: RecordingGraphMutation { events.append("first") }
        )
        let secondTrace = host.asyncTransaction(
            second,
            id: id,
            mutation: RecordingGraphMutation { events.append("second") }
        )

        XCTAssertEqual(firstTrace, secondTrace)

        host.flushTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testSameTransactionIDWithDifferentPropertyListsRemainSeparateTransactions() {
        let host = GraphHost()
        var events: [String] = []
        let id = Transaction.ID(value: 14)
        var first = Transaction()
        var second = Transaction()
        first[QueueMergeFlagKey.self] = true
        second[QueueMergeFlagKey.self] = false

        let firstTrace = host.asyncTransaction(
            first,
            id: id,
            mutation: RecordingGraphMutation { events.append("first") }
        )
        let secondTrace = host.asyncTransaction(
            second,
            id: id,
            mutation: RecordingGraphMutation { events.append("second") }
        )

        XCTAssertNotEqual(firstTrace, secondTrace)

        host.flushTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertEqual(host.data.transactionSeed, 2)
    }

    func testSameTransactionIDWithShadowedPropertyListLengthMismatchRemainsSeparateTransaction() {
        let host = GraphHost()
        var events: [String] = []
        let id = Transaction.ID(value: 15)
        var first = Transaction()
        var second = Transaction()
        first[QueueMergeFlagKey.self] = true
        second[QueueMergeFlagKey.self] = false
        second[QueueMergeFlagKey.self] = true

        let firstTrace = host.asyncTransaction(
            first,
            id: id,
            mutation: RecordingGraphMutation { events.append("first") }
        )
        let secondTrace = host.asyncTransaction(
            second,
            id: id,
            mutation: RecordingGraphMutation { events.append("second") }
        )

        XCTAssertNotEqual(firstTrace, secondTrace)

        host.flushTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertEqual(host.data.transactionSeed, 2)
    }

    func testSameTransactionIDWithMatchingShadowShapeIgnoresRepeatedKeyValues() {
        let host = GraphHost()
        var events: [String] = []
        let id = Transaction.ID(value: 16)
        let first = transactionWithQueueMergeFlagStack([true, false])
        let second = transactionWithQueueMergeFlagStack([true, true])

        let firstTrace = host.asyncTransaction(
            first,
            id: id,
            mutation: RecordingGraphMutation { events.append("first") }
        )
        let secondTrace = host.asyncTransaction(
            second,
            id: id,
            mutation: RecordingGraphMutation { events.append("second") }
        )

        XCTAssertEqual(firstTrace, secondTrace)

        host.flushTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testDifferentTransactionIDsRemainSeparateTransactions() {
        let host = GraphHost()
        var events: [String] = []

        let firstTrace = host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 20),
            mutation: RecordingGraphMutation { events.append("first") }
        )
        let secondTrace = host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 21),
            mutation: RecordingGraphMutation { events.append("second") }
        )

        XCTAssertNotEqual(firstTrace, secondTrace)

        host.flushTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertEqual(host.data.transactionSeed, 2)
    }

    func testImmediateAsyncTransactionFlushesPriorPendingBeforeQueueingNewTransaction() {
        let host = GraphHost()
        var events: [String] = []

        host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 29),
            mutation: RecordingGraphMutation { events.append("deferred") }
        )
        host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 30),
            mutation: RecordingGraphMutation { events.append("immediate") },
            style: .immediate,
            mayDeferUpdate: false
        )

        XCTAssertEqual(events, ["deferred"])
        XCTAssertTrue(host.hasPendingTransactions)
        XCTAssertFalse(host.isUpdating)
        XCTAssertEqual(host.data.transactionSeed, 1)

        host.flushTransactions()

        XCTAssertEqual(events, ["deferred", "immediate"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 2)
    }

    func testImmediateAsyncTransactionDuringUpdateQueuesWithoutNestedFlush() {
        let host = GraphHost()
        var events: [String] = []

        host.runTransaction {
            host.asyncTransaction(
                Transaction(),
                id: Transaction.ID(value: 31),
                mutation: RecordingGraphMutation { events.append("immediate") },
                style: .immediate,
                mayDeferUpdate: false
            )
            XCTAssertTrue(host.hasPendingTransactions)
            XCTAssertTrue(events.isEmpty)
        }

        XCTAssertTrue(host.hasPendingTransactions)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(host.isUpdating)
        XCTAssertEqual(host.data.transactionSeed, 1)

        host.flushTransactions()

        XCTAssertEqual(events, ["immediate"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 2)
    }

    func testFlushProcessesSnapshotAndLeavesReentrantTransactionsPending() {
        let host = GraphHost()
        var events: [String] = []

        host.asyncTransaction(
            Transaction(),
            id: Transaction.ID(value: 40),
            mutation: RecordingGraphMutation {
                events.append("outer")
                host.asyncTransaction(
                    Transaction(),
                    id: Transaction.ID(value: 41),
                    mutation: RecordingGraphMutation { events.append("nested") }
                )
            }
        )

        host.flushTransactions()

        XCTAssertEqual(events, ["outer"])
        XCTAssertTrue(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)

        host.flushTransactions()

        XCTAssertEqual(events, ["outer", "nested"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 2)
    }

    func testTransactionIDStoresFourByteHashableValue() {
        let first = Transaction.ID(value: 0xffff_ffff)
        let matching = Transaction.ID(value: 0xffff_ffff)
        let different = Transaction.ID(value: 0xffff_fffe)

        XCTAssertEqual(first, matching)
        XCTAssertNotEqual(first, different)
        XCTAssertTrue(Set([first]).contains(matching))
    }
}

private struct RecordingGraphMutation: GraphMutation {
    var body: () -> Void

    func apply() {
        body()
    }
}

private final class AsyncCombineStorage {
    var events: [String] = []
}

private struct CombiningAsyncMutation: GraphMutation {
    var name: String
    var storage: AsyncCombineStorage

    func apply() {
        storage.events.append("apply:\(name)")
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? CombiningAsyncMutation else {
            return false
        }
        storage.events.append("combine:\(name)+\(mutation.name)")
        name += "+\(mutation.name)"
        return true
    }
}

private struct QueueMergeFlagKey: TransactionKey {
    static let defaultValue = false
}

private func transactionWithQueueMergeFlagStack(_ values: [Bool]) -> Transaction {
    var transaction = Transaction()
    for value in values.reversed() {
        transaction.plist.prependValue(value, for: Transaction.TransactionKeyItem<QueueMergeFlagKey>.self)
    }
    return transaction
}
